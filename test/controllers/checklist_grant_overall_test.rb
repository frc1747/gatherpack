require "test_helper"
require_relative "../support/checklists_world"

# A grant shows the overall only when it says so, like the items it lists;
# those who run the checklist still see everything.
class ChecklistGrantOverallTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include ChecklistsWorld

  setup do
    host! "localhost"
    build_checklists_world
    @checklist = create_world_checklist
    add_rule(@checklist, :include, :team, team_id: @members.id)
    @login = add_item(@checklist, :has_login, "Login")
    @secret = add_item(@checklist, :has_login, "Secret")
    @crewmate = create_world_person("Crewmate", @crew)
    refresh(@checklist)
  end

  test "a grant without the overall shows its items and no overall" do
    @checklist.checklist_grants.create!(team: @crew, access: :full, overall: false, item_ids: [ @login.id ], created_by: person(:admin))

    visibility = Checklists::Visibility.new(@checklist, @crewmate)
    assert_nil visibility.access(nil, person(:member).id)
    assert_equal :full, visibility.access(@login, person(:member).id)
    assert_nil visibility.access(@secret, person(:member).id)

    status = Checklists::Reader.new(@checklist, @crewmate).status_for([ person(:member) ])[person(:member).id]
    assert_nil status.overall
    assert_equal [ @login ], status.items.map(&:item)
  end

  test "a grant keeps showing the overall by default" do
    grant = @checklist.checklist_grants.create!(team: @crew, access: :status, item_ids: [ @login.id ], created_by: person(:admin))
    assert grant.overall?
    assert_equal :status, Checklists::Visibility.new(@checklist, @crewmate).access(nil, person(:member).id)
    assert_equal [ "Overall", "Login" ], grant.shown_labels
  end

  test "a grant must show the overall or an item" do
    grant = @checklist.checklist_grants.new(team: @crew, access: :full, overall: false, item_ids: [])
    assert_not grant.valid?
    assert_includes grant.errors.full_messages, "Pick the overall or at least one item"
  end

  test "the report leaves out the Overall column for a grantee, and managers still see it and every item" do
    @checklist.checklist_grants.create!(team: @crew, access: :full, overall: false, item_ids: [ @login.id ], created_by: person(:admin))

    with_feature do
      sign_in @crewmate.user
      get checklist_path(@checklist)
      assert_response :success
      assert_select "th", text: /Overall/, count: 0
      assert_select "th", text: /Login/
      assert_select "th", text: /Secret/, count: 0
      assert_select "input[data-checklist-report-target=notDone]", count: 0
      assert_match "MemberTwo World", response.body

      sign_in person(:club_manager).user
      get checklist_path(@checklist)
      assert_response :success
      assert_select "th", text: /Overall/
      assert_select "th", text: /Login/
      assert_select "th", text: /Secret/
    end
  end

  test "the Give access form sets the overall, and the list says what a grant shows" do
    with_feature do
      sign_in person(:club_manager).user
      post checklist_checklist_grants_path(@checklist), params: { checklist_grant: { team_id: @crew.id, access: "full", overall: "0", item_ids: [ @login.id ] } }
      assert_response :see_other
      assert_not @checklist.checklist_grants.sole.overall?

      get edit_checklist_path(@checklist)
      assert_select "#access li span", text: /Crew members: Login\s+\(full\)/
      assert_select "#access input[type=checkbox][name='checklist_grant[overall]'][checked]"
    end
  end

  test "a copy keeps whether a grant shows the overall" do
    @checklist.checklist_grants.create!(team: @crew, access: :full, overall: false, item_ids: [ @login.id ], created_by: person(:admin))
    copy = Checklists::Copier.new(@checklist).call(title: "Trip copy", by: person(:club_manager))
    assert_not copy.checklist_grants.sole.overall?
  end
end
