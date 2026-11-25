require "test_helper"
require_relative "../support/accounting_world"

# The gateway edit form asks each gateway type for its settings' inputs
# (GatewayFieldInput): the ledger source's are tick boxes and choices.
class AccountingGatewayInputsTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include AccountingWorld

  setup do
    host! "localhost"
    @builder = create_accounting_user("Builder", architect: true)
    @members = create_ledger_team("Member ledgers")
    @club = create_ledger_team("Club accounts")
    @scholarship = LedgerTag.create!(name: "Scholarship")
    @source = create_ledger_source(ledger_team_ids: @members.neat_id, credit_tag_ids: @scholarship.id)
    sign_in @builder
  end

  test "the ledger source's form shows tick boxes and choices with directions" do
    get edit_gateway_path(@source)

    assert_response :success
    assert_select "fieldset legend", text: "Which teams' ledgers"
    assert_select "input[type=checkbox][name='gateway[ledger_team_ids][]'][value=?][checked]", @members.neat_id
    assert_select "input[type=checkbox][name='gateway[ledger_team_ids][]'][value=?]:not([checked])", @club.neat_id
    assert_select "input[type=hidden][name='gateway[ledger_team_ids][]'][value='']"
    assert_select "input[type=checkbox][name='gateway[credit_tag_ids][]'][value=?][checked]", @scholarship.neat_id
    assert_select "select[name='gateway[charge_sign]'] option[selected][value=negative]"
    assert_select "select[name='gateway[new_ledger_team_id]'] option[value='']", text: "None"
    assert_select "select[name='gateway[new_ledger_team_id]'] option[value=?]", @club.neat_id
    assert_select ".form-text", text: /Leave every box empty to use every team's ledgers\./
    assert_select "textarea[name^='gateway[']", count: 0
  end

  test "saving stores the chosen ids, and clearing every box means every team" do
    patch gateway_path(@source), params: { gateway: { name: "Member ledgers",
      ledger_team_ids: [ "", @members.neat_id, @club.neat_id ], credit_tag_ids: [ "" ],
      charge_sign: "positive", new_ledger_team_id: @club.neat_id } }

    assert_redirected_to gateway_path(@source)
    @source.reload
    assert_equal "#{@members.neat_id} #{@club.neat_id}", @source.ledger_team_ids
    assert_equal [ @members, @club ].map(&:id).sort, @source.ledger_teams.map(&:id).sort
    assert_equal "", @source.credit_tag_ids
    assert_empty @source.credit_tags
    assert_equal "positive", @source.charge_sign
    assert_equal @club, @source.new_ledger_team

    patch gateway_path(@source), params: { gateway: { name: "Member ledgers", ledger_team_ids: [ "" ] } }
    assert @source.reload.covers_team?(create_ledger_team("Anyone").id)
  end

  test "settings stored as text before still read" do
    @source.update!(ledger_team_ids: "#{@members.neat_id}, #{@club.id}")

    assert_equal [ @members, @club ].map(&:id).sort, @source.ledger_teams.map(&:id).sort
  end

  test "a gateway without field inputs keeps its plain inputs" do
    stripe = Gateway::StripeGateway.create!(name: "Card payments")

    assert_nil stripe.field_input(:public_key)
    get edit_gateway_path(stripe)

    assert_response :success
    assert_select "label.form-label", text: "public_key"
    assert_select "textarea.form-control[name='gateway[public_key]']"
    assert_select "textarea.form-control[name='gateway[test_mode]']"
    assert_select "input[type=password][name='gateway[secret_key]'][autocomplete='new-password']"
    assert_select "input[type=checkbox], select[name^='gateway[']", count: 0
  end
end
