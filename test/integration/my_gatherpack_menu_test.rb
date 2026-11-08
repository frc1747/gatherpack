require "test_helper"
require "my_gatherpack_test_helper"

class MyGatherpackMenuTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include MyGatherpackTestHelper

  MEMBER_TOP = [ "Home", "My Hours", "Calendar", "Teams", "Announcements" ].freeze
  MEMBER_MORE = %w[People Badges Tokens Ledgers Budgets Mailboxes Questions Shortcuts Pages].freeze
  TEAM_MANAGE = [ "People", "Teams", "Time Clock", "Badges", "Tokens", "Ledgers", "Budgets", "Mailboxes", "Pages" ].freeze
  # These destinations belong to branches this one doesn't depend on.
  STUBBED_PATHS = %i[forms_path family_path commitments_path].freeze

  setup do
    host! "localhost"
    @plugins = GatherPack::Features.instance_variable_get(:@plugins)
    @original_plugins = @plugins.dup
    @original_checks = MyGatherpack::Menu.manager_checks.dup
    @original_slots = GatherPack::SidebarSlots.instance_variable_get(:@slots).dup
    @original_root_attributes = GatherPack::SidebarSlots.instance_variable_get(:@root_attributes).dup
    @original_view_paths = ApplicationController.view_paths
    STUBBED_PATHS.each { |name| NavHelper.define_method(name) { "/calendar" } }
    turn_on_my_gatherpack
    @member = create_login("Morgan")
  end

  teardown do
    restore_my_gatherpack
    STUBBED_PATHS.each { |name| NavHelper.remove_method(name) }
    ApplicationController.view_paths = @original_view_paths
    @plugins.replace(@original_plugins)
    MyGatherpack::Menu.manager_checks.replace(@original_checks)
    GatherPack::SidebarSlots.instance_variable_set(:@slots, @original_slots)
    GatherPack::SidebarSlots.instance_variable_set(:@root_attributes, @original_root_attributes)
  end

  test "the flag is off by default and its overrides sit above the skin's" do
    feature = GatherPack::Features.all.find { |f| f.key == :my_gatherpack }
    override = GatherPack::ViewOverrides.all.find { |o| o.key == :my_gatherpack }

    assert_equal false, feature.default_enabled
    assert_equal 20, override.position
  end

  test "a member sees the short list and More, with no Manage" do
    assert_equal({ "top" => MEMBER_TOP, "more" => MEMBER_MORE }, menu_for(@member))
  end

  test "More starts closed" do
    menu_for(@member)

    assert_select "details[data-menu-group=more]:not([open]) summary", text: "More"
  end

  test "a guardian also sees Family" do
    register_items nav_item("Family", :family_path, visible: ->(user) { user == @member })

    groups = menu_for(@member)
    assert_equal [ "Family" ], groups["family"]
    assert_equal MEMBER_TOP, groups["top"]

    assert_nil menu_for(create_login("Quinn"))["family"]
  end

  test "a team manager sees Manage, and each item once outside the top group" do
    manager = create_login("Riley")
    Membership.create!(person: manager.person, team: teams(:one), manager: true)

    assert_equal({ "top" => MEMBER_TOP, "more" => %w[Questions Shortcuts], "manage" => TEAM_MANAGE }, menu_for(manager))
  end

  test "a Forms creator who manages no team sees only what their check opens" do
    creator = create_login("Sage")
    register_items nav_item("Forms", :forms_path)
    MyGatherpack::Menu.register_manager_check(:forms_creator, paths: [ :forms_path ]) { |person| person == creator.person }

    groups = menu_for(creator)
    assert_equal [ "Forms" ], groups["manage"]
    assert_includes groups["top"], "Forms"
    assert_includes groups["more"], "Tokens"

    assert_nil menu_for(@member)["manage"]
  end

  test "an organizer's item moves from More to Manage" do
    organizer = create_login("Tatum")
    register_items nav_item("Commitments", :commitments_path)
    MyGatherpack::Menu.register_manager_check(:organizer, paths: [ :commitments_path ]) { |person| person == organizer.person }

    groups = menu_for(organizer)
    assert_equal [ "Commitments" ], groups["manage"]
    assert_not_includes groups["more"], "Commitments"

    assert_includes menu_for(@member)["more"], "Commitments"
  end

  test "an admin sees Manage and the admin sections unchanged" do
    groups = menu_for(create_login("Avery", admin: true))

    assert_equal TEAM_MANAGE, groups["manage"]
    assert_equal [ "Variables", "Reports", "Hooks", "Setup", "Audit Log" ], groups["admin"]
    assert_select "[data-menu-group=admin] h6", text: "Automation"
    assert_select "[data-menu-group=admin] h6", text: "Admin"
  end

  test "an impersonated member gets the member's menu and the impersonation block" do
    sign_in create_login("Avery", admin: true)
    post impersonate_person_path(@member.person)
    get root_path

    assert_equal({ "top" => MEMBER_TOP, "more" => MEMBER_MORE }, rendered_groups)
    assert_select ".sidebar .impersonator-label", text: /impersonating/
    assert_select ".sidebar form[action=?]", stop_impersonating_people_path
  end

  test "an item not in the table lands in More" do
    register_items nav_item("Brand New", "/calendar"), nav_item("Brand New Proc", -> { "/calendar" })

    groups = menu_for(@member)
    assert_includes groups["more"], "Brand New"
    assert_includes groups["more"], "Brand New Proc"
  end

  test "a hidden item appears in no group" do
    register_items nav_item("Not Yours", "/calendar", visible: ->(_) { false })

    assert_not_includes menu_for(@member).values.flatten, "Not Yours"
  end

  test "a section with nothing to show loses its heading" do
    assert_empty MyGatherpack::Menu.new(@member).manage

    menu_for(@member)
    assert_select "[data-menu-group=manage]", count: 0
  end

  test "a passing check with no items of its own leaves no empty Manage heading" do
    MyGatherpack::Menu.register_manager_check(:nothing_listed) { |_person| true }

    assert MyGatherpack::Menu.new(@member).manages_anything?
    assert_nil menu_for(@member)["manage"]
  end

  test "manager checks run once per request" do
    calls = 0
    MyGatherpack::Menu.register_manager_check(:counted) { |_person| calls += 1; false }
    menu = MyGatherpack::Menu.new(@member)

    2.times { menu.manages_anything? }
    menu.manage
    assert_equal 1, calls
  end

  test "My Hours is the plain page for a member" do
    menu_for(@member)

    assert_select "[data-menu-group=top] a[href=?]", time_clock_punches_path, text: /My Hours/
  end

  test "My Hours is filtered to a manager's own punches, and Time Clock is not" do
    manager = create_login("Riley")
    Membership.create!(person: manager.person, team: teams(:one), manager: true)
    menu_for(manager)

    own = time_clock_punches_path(q: { person_id_eq: manager.person.id })
    assert_select "[data-menu-group=top] a[href=?]", own, text: /My Hours/
    assert_select "[data-menu-group=manage] a[href=?]", time_clock_punches_path, text: /Time Clock/
  end

  test "the My Hours filter keeps only that person's punches" do
    mine = TimeClockPunch.create!(person: @member.person, start_time: 2.hours.ago, created_by: @member)
    TimeClockPunch.create!(person: create_login("Quinn").person, start_time: 1.hour.ago, created_by: @member)

    assert_equal [ mine ], TimeClockPunch.ransack(person_id_eq: @member.person.id).result.to_a
  end

  test "a member with no Manage section gets what they get today at a manager's page" do
    [ variables_path, audit_logs_path, setup_path, new_team_path ].each do |path|
      sign_in @member
      get path
      with_flag = [ response.status, response.location ]

      Settings[:feature_my_gatherpack] = "false"
      get path
      assert_equal [ response.status, response.location ], with_flag, path
      Settings[:feature_my_gatherpack] = "true"
    end

    get variables_path
    assert_not_equal 200, response.status
  end

  test "the sidebar names the site and offers search, with no top bar at md and up" do
    sign_in @member
    get root_path

    assert_select "[data-site-brand] a[href=?]", root_path, text: /Northwind Community/
    assert_select "[data-site-brand] form[role=search][action=?] input[name=q]", search_path
    assert_select "header.navbar.d-md-none"
    assert_includes response.body, "<title>Northwind Community</title>"
  end

  test "a blank site title falls back to the product name" do
    Settings[:title] = ""
    sign_in @member
    get root_path

    assert_select "[data-site-brand] a", text: /GatherPack/
    assert_select "header.navbar .navbar-brand", text: /GatherPack/
    assert_includes response.body, "<title>GatherPack</title>"
  end

  test "with the flag off, a blank site title renders as it does today" do
    Settings[:feature_my_gatherpack] = "false"
    Settings[:title] = ""
    sign_in @member
    get root_path

    assert_includes response.body, "<title>  | </title>"
  end

  test "the feature's name is never rendered" do
    sign_in create_login("Avery", admin: true)

    [ root_path, teams_path, calendar_index_path ].each do |path|
      get path
      assert_no_match "My GatherPack", response.body, path
    end
  end

  test "sidebar slots and root attributes still render" do
    ApplicationController.prepend_view_path(Rails.root.join("test/fixtures/views"))
    GatherPack::SidebarSlots.register(:early, partial: "sidebar_slots_test/early")
    GatherPack::SidebarSlots.root_attributes(:probe) { { id: "permanent-sidebar", data: { probe: "yes" } } }
    sign_in @member
    get root_path

    assert_select ".sidebar#permanent-sidebar[data-probe=yes]"
    assert_match "early slot", response.body
  end

  test "with the flag off, today's sidebar and top bar come back" do
    Settings[:feature_my_gatherpack] = "false"
    sign_in @member
    get root_path

    assert_select "[data-menu-group]", count: 0
    assert_select "[data-site-brand]", count: 0
    assert_select "header.navbar.d-md-none", count: 0
    assert_select ".sidebar a", text: /Dashboard/
    assert_select ".sidebar h6", text: "People"
    assert_includes response.body, "<title> Northwind Community | </title>"
    assert_not_includes GatherPack::ViewOverrides.active_paths(nil), Rails.root.join("app/view_overrides/my_gatherpack").to_s
  end

  private

  def nav_item(label, path, **options)
    GatherPack::Feature::NavItem.new(label: label, path: path, icon: "flag", **options)
  end

  def register_items(*items)
    GatherPack::Features.register(GatherPack::Feature.new(
      key: :"menu_test_#{items.first.label.parameterize}", label: "Menu Test", toggleable: false,
      nav_section: "Menu Test", nav_items: items
    ))
  end

  def menu_for(user)
    sign_in user
    get root_path
    assert_response :success
    rendered_groups
  end

  def rendered_groups
    css_select("[data-menu-group]").to_h do |group|
      [ group["data-menu-group"], group.css("a").map { |link| link.text.strip } ]
    end
  end
end
