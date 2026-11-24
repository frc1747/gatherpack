require "test_helper"
require "my_gatherpack_test_helper"

# The sidebar grouped by job: the Sign-ups & forms run, report Pages, Manage's
# parts and pins.
class MyGatherpackMenuByJobTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include MyGatherpackTestHelper

  # These destinations belong to branches this one doesn't depend on.
  STUBBED_PATHS = %i[forms_path checklists_path signup_sheets_path].freeze

  setup do
    host! "localhost"
    @plugins = GatherPack::Features.instance_variable_get(:@plugins)
    @original_plugins = @plugins.dup
    @original_checks = MyGatherpack::Menu.manager_checks.dup
    STUBBED_PATHS.each { |name| NavHelper.define_method(name) { "/calendar" } }
    turn_on_my_gatherpack
    @member = create_login("Morgan")
    @manager = create_login("Riley")
    Membership.create!(person: @manager.person, team: teams(:one), manager: true)
  end

  teardown do
    restore_my_gatherpack
    STUBBED_PATHS.each { |name| NavHelper.remove_method(name) }
    @plugins.replace(@original_plugins)
    MyGatherpack::Menu.manager_checks.replace(@original_checks)
  end

  test "Sign-ups, Forms and Checklists run together after Home, and Checklists leaves its section" do
    register_items "People", nav_item("Checklists", :checklists_path)
    register_items "Communication", nav_item("Forms", :forms_path), nav_item("Sign-ups", :signup_sheets_path)

    menu = MyGatherpack::Menu.new(@member)
    assert_equal [ "Home", "Sign-ups", "Forms", "Checklists", "My Hours", "Calendar", "Teams", "Announcements" ], menu.top.map(&:label)
    assert_not_includes menu.sections.flat_map { |_name, items| items.map(&:label) }, "Checklists"
  end

  test "Reports lists ticked Pages a member may open, by title, then All pages" do
    report("Zone totals")
    report("Attendance")
    report("Leaders only", viewer: "manager", team: teams(:one))
    Page.create!(title: "Not ticked", content: "x", viewer: "user", editor: "admin")

    groups = menu_for(@member)
    assert_equal [ "Attendance", "Zone totals", "All pages" ], groups["reports"]
    assert_select "[data-menu-group=reports] > h6", text: "Reports"
    assert_equal %w[top reports], css_select("[data-menu-group]").map { |group| group["data-menu-group"] }.first(2)
  end

  test "a manager also sees their team's manager-level reports" do
    report("Attendance")
    report("Leaders only", viewer: "manager", team: teams(:one))

    assert_equal [ "Attendance", "Leaders only", "All pages" ], menu_for(@manager)["reports"]
  end

  test "no ticked Pages means no Reports heading" do
    Page.create!(title: "Not ticked", content: "x", viewer: "user", editor: "admin")

    assert_nil menu_for(@member)["reports"]
    assert_select ".sidebar h6", text: "Reports", count: 0
  end

  test "Manage's parts come in order under their headings, with Pages first in Content" do
    menu_for(@manager)

    assert_equal %w[People Time Money Content], css_select("[data-menu-group=manage] [data-menu-part] > h6").map { |heading| heading.text.strip }
    parts = css_select("[data-menu-part]").to_h { |part| [ part["data-menu-part"], part.css("a").map { |link| link.text.strip } ] }
    assert_equal({ "people" => %w[People Teams Badges Tokens], "time" => [ "Time Clock" ], "money" => %w[Ledgers Budgets],
      "content" => %w[Pages Mailboxes Shortcuts] }, parts)
    assert_select "[data-menu-part=people] h6 button[aria-expanded=true][aria-controls=mg-menu-part-people]"
  end

  test "a part with nothing in it for this person is dropped" do
    organizer = create_login("Tatum")
    MyGatherpack::Menu.register_manager_check(:people_only, paths: [ :people_path ]) { |person| person == organizer.person }

    assert_equal [ [ :people, "People", [ "People" ] ] ], MyGatherpack::Menu.new(organizer).manage_parts.map { |key, heading, items| [ key, heading, items.map(&:label) ] }
    menu_for(organizer)
    assert_equal [ "People" ], css_select("[data-menu-part] > h6").map { |heading| heading.text.strip }
  end

  test "a checklist creator and a Forms creator see Checklists and Forms once, in the top run" do
    register_items "People", nav_item("Checklists", :checklists_path)
    register_items "Communication", nav_item("Forms", :forms_path), nav_item("Sign-ups", :signup_sheets_path)
    creator = create_login("Sage")
    everything = [ :checklists_path, :forms_path, :signup_sheets_path ]
    MyGatherpack::Menu.register_manager_check(:creator, paths: everything) { |person| [ creator.person, @manager.person ].include?(person) }

    [ creator, @manager ].each do |user|
      groups = menu_for(user)
      [ "Sign-ups", "Forms", "Checklists" ].each do |label|
        assert_equal 1, groups.values.flatten.count(label), "#{label} for #{user.person.first_name}"
        assert_includes groups["top"], label
      end
    end
    assert_nil menu_for(creator)["manage"]
  end

  test "a Manage item the table places in no part comes last, under no heading" do
    register_items "Menu Test", nav_item("Organizing", :organizing_path)
    NavHelper.define_method(:organizing_path) { "/calendar" }
    MyGatherpack::Menu.register_manager_check(:organizing, paths: [ :organizing_path ]) { |person| person == @manager.person }

    parts = MyGatherpack::Menu.new(@manager).manage_parts
    assert_equal [ :people, :time, :money, :content, nil ], parts.map(&:first)
    assert_equal [ "Organizing" ], parts.last.last.map(&:label)
    assert_equal "Organizing", menu_for(@manager)["manage"].last
  ensure
    NavHelper.remove_method(:organizing_path)
  end

  test "a pin answers with a stream that redraws only the menu, for the page it was clicked on" do
    sign_in @member
    post menu_pins_path, params: { path_key: "calendar_index_path", from: teams_path }, as: :turbo_stream

    assert_equal "text/vnd.turbo-stream.html", response.media_type
    assert_select "turbo-stream[action=update][target=mg-menu]", count: 1
    assert_select "turbo-stream", count: 1
    assert_select "turbo-stream template [data-menu-group=pinned] a", text: /Calendar/
    assert_select "turbo-stream template [data-menu-group=top] a.active", text: /Teams/
  end

  test "pinning adds the item to Pinned and leaves it where it was" do
    sign_in @member
    get root_path
    assert_select "[data-menu-group=top] button.mg-pin[aria-label=?]", "Pin Calendar to the top"

    post menu_pins_path, params: { path_key: "calendar_index_path" }, as: :turbo_stream
    assert_response :success
    post menu_pins_path, params: { path_key: "teams_path" }, as: :turbo_stream

    groups = menu_for(@member)
    assert_equal %w[Calendar Teams], groups["pinned"]
    assert_includes groups["top"], "Calendar"
    assert_equal "pinned", css_select("[data-menu-group]").first["data-menu-group"]
    assert_select "[data-menu-group=pinned] > h6", text: "Pinned"
    assert_select "button.mg-pin[aria-label=?]", "Unpin Calendar", count: 2
  end

  test "pins come back in another session" do
    sign_in @member
    post menu_pins_path, params: { path_key: "calendar_index_path" }, as: :turbo_stream
    sign_out @member
    reset!
    host! "localhost"

    assert_equal [ "Calendar" ], menu_for(@member)["pinned"]
  end

  test "unpinning removes the item from Pinned" do
    sign_in @member
    post menu_pins_path, params: { path_key: "calendar_index_path" }, as: :turbo_stream
    delete menu_pin_path("calendar_index_path"), as: :turbo_stream
    assert_response :success

    assert_nil menu_for(@member)["pinned"]
    assert_equal 0, MenuPin.where(user: @member).count
  end

  test "My Hours and a report Page can be pinned" do
    page = report("Attendance")
    sign_in @member
    post menu_pins_path, params: { path_key: "my_hours" }, as: :turbo_stream
    post menu_pins_path, params: { path_key: MenuPin.page_key(page) }, as: :turbo_stream

    assert_equal [ "My Hours", "Attendance" ], menu_for(@member)["pinned"]
  end

  test "deleting a pinned Page removes its pins" do
    page = report("Attendance")
    MenuPin.create!(user: @member, path_key: MenuPin.page_key(page))
    MenuPin.create!(user: @member, path_key: "calendar_index_path")

    page.destroy!
    assert_equal [ "calendar_index_path" ], MenuPin.where(user: @member).pluck(:path_key)
  end

  test "a pin to an item the person can't see isn't shown, and is kept" do
    page = report("Leaders only", viewer: "manager", team: teams(:one))
    MenuPin.create!(user: @member, path_key: MenuPin.page_key(page))
    MenuPin.create!(user: @member, path_key: "widgets_path")
    MenuPin.create!(user: @member, path_key: "people_path")

    assert_equal [ "People" ], menu_for(@member)["pinned"]
    assert_equal 3, MenuPin.where(user: @member).count
  end

  test "a person can only change their own pins" do
    MenuPin.create!(user: @manager, path_key: "calendar_index_path")
    sign_in @member

    delete menu_pin_path("calendar_index_path"), as: :turbo_stream
    assert_response :not_found
    sign_in @member # the 404 page wrote no session cookie
    post menu_pins_path, params: { path_key: "teams_path" }, as: :turbo_stream
    assert_response :success

    assert_equal [ "calendar_index_path" ], MenuPin.where(user: @manager).pluck(:path_key)
    assert_equal [ "teams_path" ], MenuPin.where(user: @member).pluck(:path_key)
  end

  test "pins need the flag and a signed-in person" do
    post menu_pins_path, params: { path_key: "teams_path" }, as: :turbo_stream
    assert_redirected_to new_user_session_path

    Settings[:feature_my_gatherpack] = "false"
    sign_in @member
    post menu_pins_path, params: { path_key: "teams_path" }, as: :turbo_stream
    assert_response :not_found
    assert_equal 0, MenuPin.count
  end

  test "the Page form's Show in the menu box saves, and only while the flag is on" do
    page = Page.create!(title: "Attendance", content: "x", viewer: "user", editor: "admin")
    sign_in create_login("Avery", admin: true)

    get edit_page_path(page)
    assert_select "input[type=checkbox][name=?]", "page[show_in_menu]"
    assert_select "label", text: "Show in the menu"
    patch page_path(page), params: { page: { show_in_menu: "1" } }
    assert page.reload.show_in_menu

    Settings[:feature_my_gatherpack] = "false"
    get edit_page_path(page)
    assert_select "input[name=?]", "page[show_in_menu]", count: 0
    patch page_path(page), params: { page: { show_in_menu: "0" } }
    assert page.reload.show_in_menu
  end

  test "with the flag off, ticked Pages and pins stay out of the sidebar" do
    report("Attendance")
    MenuPin.create!(user: @member, path_key: "calendar_index_path")
    Settings[:feature_my_gatherpack] = "false"
    sign_in @member
    get root_path

    assert_select ".sidebar a", text: /Attendance/, count: 0
    assert_select ".sidebar .mg-pin", count: 0
    assert_select ".sidebar h6", text: "Pinned", count: 0
  end

  private

  def report(title, viewer: "user", team: nil)
    Page.create!(title: title, content: "x", viewer: viewer, editor: "admin", team: team, show_in_menu: true)
  end

  def nav_item(label, path)
    GatherPack::Feature::NavItem.new(label: label, path: path, icon: "flag")
  end

  def register_items(section, *items)
    GatherPack::Features.register(GatherPack::Feature.new(
      key: :"menu_by_job_#{items.first.label.parameterize}", label: "Menu Test", toggleable: false,
      nav_section: section, nav_items: items
    ))
  end

  def menu_for(user)
    sign_in user
    get root_path
    assert_response :success
    css_select("[data-menu-group]").to_h do |group|
      [ group["data-menu-group"], group.css("a").map { |link| link.text.strip } ]
    end
  end
end
