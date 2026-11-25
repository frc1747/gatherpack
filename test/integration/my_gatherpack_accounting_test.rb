require "test_helper"
require_relative "../support/accounting_rules_world"

# Account status on the My GatherPack home page and the Family page. World:
# Nancy is linked to customer 58 and owes part of her dues; Margaret is her
# guardian, Andrew leads her team, Steven is a stranger. Flags are set in a
# throwaway store.
class MyGatherpackAccountingTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include AccountingRulesWorld

  setup do
    host! "localhost"
    @restore_settings = SettingsTestHelper.apply(feature_my_gatherpack: "true", feature_accounting: "true")
    @team = create_rule_team("Robotics")
    @laura = create_rule_person("Laura", "Callahan", admin: true)
    @nancy = create_rule_person("Nancy", "Davolio", team: @team, customer: "58")
    @margaret = create_rule_person("Margaret", "Peacock")
    add_guardian(@margaret, @nancy, by: @laura)
    @andrew = create_rule_person("Andrew", "Fuller", team: @team, manager: true)
    @steven = create_rule_person("Steven", "Buchanan")

    add_charge("58", "I1", total: 40_000, balance: 5_000, label: "Invoice 1042 · Dues", items: [ "dues" ],
      pay_url: "https://pay.example.com/1042", description: "Season dues")
    add_payment("58", "P1", total: 10_000, applied: { "I1" => 10_000 })
    add_payment("58", "CM1", total: 25_000, applied: { "I1" => 25_000 }, role: "credit", public_label: "Credit",
      description: "Hardship scholarship")

    @rule = create_rule(read_permission: "family", amount_permission: "family", show_pay_links: true, filters: { "items" => [ "dues" ] },
      milestones: [ { name: "Deposit", due_on: Date.new(2026, 10, 1), balance_at_most_percent: 50 },
                    { name: "Paid in full", due_on: Date.new(2099, 1, 15), balance_at_most_cents: 0 } ])
    evaluate(@rule)
  end

  teardown do
    @restore_settings&.call
  end

  # Home

  test "a person sees their own status, balance, next milestone and Pay online on Home, without their name" do
    sign_in @nancy.user
    get root_path

    assert_response :success
    assert_select "[data-home-section=accounting]" do
      assert_select ".mg-heading", text: "Account"
      assert_select "[data-account-row=?]", @nancy.id do
        assert_select ".mg-row-title", text: /2027 Membership Dues/
        assert_select ".mg-row-ward", false
        assert_select ".badge", text: "Partly paid"
        assert_select ".mg-row-detail", text: /Balance remaining \$50\.00 · Next: \$50\.00 by/
        # Not a tap-row action, which a phone would stretch over the row and strip of its label.
        assert_select "a.btn.btn-primary.mg-account-pay[href=?]", "https://pay.example.com/1042", text: "Pay online"
        assert_select ".mg-row-action", false
        assert_select "a[href=?]", person_accounting_path(@nancy), text: "2027 Membership Dues"
      end
    end
  end

  test "a guardian sees each ward's visible rules on Home, named" do
    trip = create_rule("Travel fee 2027", read_permission: "family", amount_permission: "admin")
    evaluate(trip)
    sign_in @margaret.user
    get root_path

    assert_select "[data-account-row=?]", @margaret.id, false
    assert_select "[data-account-row=?]", @nancy.id do
      assert_select "[data-account-rule=?] .mg-row-title", @rule.id, text: /2027 Membership Dues\s+for Nancy\s+Partly paid/
      assert_select "[data-account-rule=?] .mg-row-title", trip.id, text: /Travel fee 2027\s+for Nancy/
      assert_select ".mg-row-title .mg-row-ward", text: "for Nancy", count: 2
      assert_select "a", text: /Pay online/, count: 1
    end
  end

  test "balances and the pay link stay hidden from a guardian when amounts are the person's only" do
    @rule.update!(amount_permission: "self")
    sign_in @margaret.user
    get root_path

    assert_select "[data-account-row=?]", @nancy.id do
      assert_select ".badge", text: "Partly paid"
      assert_select ".mg-row-detail", text: "Next: Paid in full"
    end
    assert_no_match "$50.00", response.body
    assert_no_match "Pay online", response.body
  end

  test "the pay link shows only when the rule shows pay links" do
    @rule.update!(show_pay_links: false)
    sign_in @nancy.user
    get root_path

    assert_select ".mg-row-detail", text: /Balance remaining \$50\.00/
    assert_no_match "Pay online", response.body
    assert_no_match "pay.example.com", response.body
  end

  test "a paid result shows no balance and no pay link" do
    AccountingRecord.find_by(external_id: "I1").update!(balance_cents: 0)
    evaluate(@rule)
    sign_in @nancy.user
    get root_path

    assert_select "[data-account-row=?]", @nancy.id do
      assert_select ".badge", text: "Paid"
      assert_select ".mg-row-detail", false
    end
    assert_no_match "Pay online", response.body
  end

  test "nothing renders on Home for someone with no visible results" do
    [ @steven, @andrew ].each do |viewer|
      sign_in viewer.user
      get root_path

      assert_response :success
      assert_select "[data-home-section=accounting]", false
    end
  end

  test "a rule only admins may read, a turned-off rule or an error puts nothing on Home, even for admins" do
    add_guardian(@laura, @nancy, by: @laura)
    @rule.update!(read_permission: "admin", amount_permission: "admin")
    sign_in @nancy.user
    get root_path
    assert_select "[data-home-section=accounting]", false

    @rule.update!(read_permission: "family", enabled: false)
    sign_in @laura.user
    get root_path
    assert_select "[data-home-section=accounting]", false

    @rule.update!(enabled: true)
    result_for(@rule, @nancy).update!(value: AccountingRule::ERROR, details: { "error" => "boom" })
    get root_path
    assert_select "[data-home-section=accounting]", false
  end

  test "a former guardian sees nothing on Home" do
    Relationship.where(parent: @margaret, child: @nancy).destroy_all
    sign_in @margaret.user
    get root_path

    assert_response :success
    assert_select "[data-home-section=accounting]", false
    assert_no_match "Membership Dues", response.body
  end

  # Family page

  test "a ward's card shows the same line under their forms and checklists, without repeating the name" do
    sign_in @margaret.user
    get family_path

    assert_response :success
    assert_select "#{ward_card(@nancy)} [data-family-row=accounting]" do
      assert_select ".mg-row-title", text: /2027 Membership Dues/
      assert_select ".mg-row-ward", false
      assert_select ".badge", text: "Partly paid"
      assert_select ".mg-row-detail", text: /Balance remaining \$50\.00/
      assert_select "a.btn-primary.mg-account-pay[href=?]", "https://pay.example.com/1042", text: "Pay online"
    end
    assert_select "#{ward_card(@nancy)} p", text: "Nothing to show yet.", count: 0
    assert_select "#{ward_card(@nancy)} [data-family-status]", text: "All caught up"
  end

  test "an overdue account counts in what needs the guardian on the ward's card" do
    travel_to Date.new(2026, 11, 2) do
      AccountingRecord.find_by(external_id: "I1").update!(balance_cents: 30_000)
      evaluate(@rule)
      assert_equal "overdue", result_for(@rule, @nancy).value
      sign_in @margaret.user
      get family_path
    end

    assert_select "#{ward_card(@nancy)} [data-family-status]", text: "1 thing needs you"
    assert_select "#{ward_card(@nancy)} [data-family-row=accounting] .mg-row-detail", text: /Overdue: Deposit/
  end

  test "a ward's card leaves out amounts the guardian may not see, and shows no row without results" do
    @rule.update!(amount_permission: "self")
    sign_in @margaret.user
    get family_path

    assert_select "#{ward_card(@nancy)} [data-family-row=accounting] .badge", text: "Partly paid"
    assert_no_match "$50.00", response.body
    assert_no_match "Pay online", response.body

    @rule.update!(read_permission: "self")
    get family_path

    assert_select "#{ward_card(@nancy)} [data-family-row=accounting]", false
    assert_select "#{ward_card(@nancy)} p", text: "Nothing to show yet."
  end

  test "a former guardian's ward drops off the Family page and Home" do
    robin = create_rule_person("Robin", "Peacock", customer: "61")
    robin.update!(birthday: Date.current - 8.years)
    @nancy.update!(birthday: Date.current - 20.years)
    add_guardian(@margaret, robin, by: @laura)
    evaluate(@rule)
    sign_in @margaret.user

    with_settings(guardianship_age_limit: "18") do
      get family_path
      assert_select ward_card(robin)
      assert_select ward_card(@nancy), false
      assert_select "[data-account-row=?]", @nancy.id, false

      get root_path
      assert_select "[data-account-row=?]", @nancy.id, false
    end
  end

  # Credit privacy

  test "a credit with a scholarship memo shows as Credit, never its reason, on Home and Family" do
    sign_in @margaret.user
    [ root_path, family_path ].each do |path|
      get path

      assert_select "[data-account-row=?]", @nancy.id
      assert_no_match(/scholarship|Season dues/i, response.body)
    end
  end

  # Feature off

  test "with accounting off, Home and the Family page show no account rows" do
    sign_in @margaret.user
    with_accounting(false) do
      get root_path
      assert_select ".mg-home"
      assert_select "[data-home-section=accounting]", false

      get family_path
      assert_select ward_card(@nancy)
      assert_select "[data-family-row=accounting]", false
    end
  end

  test "with My GatherPack off, the dashboard shows no account section" do
    sign_in @nancy.user
    with_settings(feature_my_gatherpack: "false") { get root_path }

    assert_response :success
    assert_select ".mg-home", false
    assert_select "[data-account-row]", false
  end

  private
    def ward_card(ward)
      "##{dom_id(ward, :family)}"
    end
end
