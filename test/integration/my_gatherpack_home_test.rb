require "test_helper"
require "my_gatherpack_test_helper"

class MyGatherpackHomeTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include MyGatherpackTestHelper

  FEATURE_SETTINGS = %i[feature_events feature_time_tracking].freeze

  setup do
    host! "localhost"
    @original_sections = MyGatherpack.sections.dup
    @original_view_paths = ApplicationController.view_paths
    ApplicationController.prepend_view_path(Rails.root.join("test/fixtures/views"))
    @saved_feature_values = FEATURE_SETTINGS.to_h { |key| [ key, Settings.get(key).instance_variable_get(:@value) ] }
    turn_on_my_gatherpack
    @member = create_login("Morgan")
    Membership.create!(person: @member.person, team: teams(:one))
    sign_in @member
  end

  teardown do
    restore_my_gatherpack
    @saved_feature_values.each { |key, value| Settings.get(key).instance_variable_set(:@value, value) }
    ApplicationController.view_paths = @original_view_paths
    MyGatherpack.sections.replace(@original_sections)
  end

  test "with the flag off the dashboard is today's" do
    Settings[:feature_my_gatherpack] = "false"

    get root_path

    assert_response :success
    assert_select ".mg-home", false
    assert_select "h2", text: "Calendar"
  end

  test "with nothing to do the heading says so and empty sections stay out" do
    get root_path

    assert_response :success
    assert_select "h1", text: "Hi Morgan. You're all caught up."
    assert_select ".mg-heading", false
    assert_select ".mg-status", false
  end

  test "the page names the site, never the feature" do
    get root_path

    assert_select "title", text: "Northwind Community"
    assert_no_match "My GatherPack", response.body
  end

  test "the heading counts to-do items" do
    register_todos item("Only one")
    get root_path
    assert_select "h1", text: "Hi Morgan. You have 1 thing to do."

    register_todos item("One"), item("Two"), item("Three")
    get root_path
    assert_select "h1", text: "Hi Morgan. You have 3 things to do."
  end

  test "to-do rows merge across sections: past due, then nearest, then undated" do
    MyGatherpack.register_section(:todo_a, partial: "my_gatherpack/todo_row", column: :todo, position: 10,
      items: -> { [ MyGatherpack::Item.new(title: "Undated", action: "Open", path: "/a"),
                    MyGatherpack::Item.new(title: "Next month", at: 1.month.from_now, action: "Open", path: "/b") ] })
    MyGatherpack.register_section(:todo_b, partial: "my_gatherpack/todo_row", column: :todo, position: 20,
      items: -> { [ MyGatherpack::Item.new(title: "Tomorrow", at: 1.day.from_now, action: "Open", path: "/c"),
                    MyGatherpack::Item.new(title: "Last week", at: 1.week.ago, action: "Open", path: "/d") ] })

    get root_path

    assert_equal [ "Last week", "Tomorrow", "Next month", "Undated" ], row_titles("todo")
  end

  test "a to-do row has one specific button, and names a ward only on that ward's row" do
    register_todos item("Permission slip", ward: "Maya", action: "Fill out"), item("My own form", action: "See shifts")

    get root_path

    rows = css_select("[data-home-column=todo] .mg-row")
    assert_equal [ "Fill out" ], rows.first.css("a.btn").map { |link| link.text.strip }
    assert_includes rows.first.css(".mg-row-ward").text, "for Maya"
    assert_empty rows.last.css(".mg-row-ward")
  end

  test "coming up shows the viewer's next five events, soonest first" do
    6.downto(1) { |days| create_event("In #{days} days", days.days.from_now) }
    create_event("Already over", 2.days.ago)
    create_event("Other team's event", 1.hour.from_now, team: teams(:two))

    get root_path

    assert_equal (1..5).map { |days| "In #{days} days" }, row_titles("coming_up")
  end

  test "events leave coming up when the feature is off" do
    create_event("Practice", 1.day.from_now)
    Settings[:feature_events] = "false"

    get root_path

    assert_response :success
    assert_select "[data-home-column=coming_up]", false
  end

  test "the clocked-in status shows only for the viewer's own open punch" do
    punch(people(:one), 1.hour.ago, nil)
    punch(@member.person, 3.hours.ago, 2.hours.ago)
    get root_path
    assert_select ".mg-status", false

    since = Time.zone.now.change(usec: 0) - 1.minute
    punch(@member.person, since, nil)
    get root_path
    assert_select ".mg-status", text: /Clocked in since/

    Settings[:feature_time_tracking] = "false"
    get root_path
    assert_select ".mg-status", false
  end

  test "widget slots still render in their placements" do
    get root_path

    assert_select ".mg-home > [data-widget-slot=top]"
    assert_select ".col-lg-8 > [data-widget-slot=left]"
    assert_select ".col-lg-4 > [data-widget-slot=right]"
  end

  test "right widgets sit above the announcements" do
    create_announcement("Team shirts are in")

    get root_path

    assert_operator response.body.index('data-widget-slot="right"'), :<, response.body.index("Team shirts are in")
  end

  test "latest shows the newest announcement first and only what the viewer may see" do
    create_announcement("Older", start: 2.days.ago)
    create_announcement("Newer", start: 1.hour.ago)
    create_announcement("Other team's news", team: teams(:two))

    get root_path

    assert_equal %w[Newer Older], css_select("[data-home-section=announcements] .mg-row-title").map { |title| title.text.strip }
    assert_no_match "Other team&#39;s news", response.body
  end

  test "the calendar, shortcuts and ledgers stay below" do
    Shortcut.create!(name: "Handbook", icon: "book", color: "#336699", target: "/handbook", team: teams(:one))

    get root_path

    assert_select "h2", text: "Calendar"
    assert_select "h2", text: "Your Shortcuts"
    assert_select "h2", text: "Ledgers"
    assert_select "a[href='/handbook'][style*='#336699']", text: /Handbook/
  end

  test "a shortcut can't write a script link or styles into the page" do
    shortcut = Shortcut.new(name: "Sneaky", icon: "book", color: "red; background: url(x)", target: "javascript:alert(1)", team: teams(:one))
    shortcut.save!(validate: false)

    get root_path

    assert_select "a[href='#']", text: /Sneaky/
    assert_no_match "url(x)", response.body
  end

  test "a registered section appears and one that renders nothing doesn't" do
    register_block :shown, "my_gatherpack_home_test/block"
    get root_path
    assert_select "#registered-block"

    MyGatherpack.sections.delete(:shown)
    register_block :empty, "my_gatherpack_home_test/blank"
    get root_path
    assert_select "#registered-block", false
    assert_select ".col-lg-4 > [data-widget-slot=right]"
  end

  test "a disabled feature's section doesn't appear or run" do
    MyGatherpack.register_section(:off, partial: "my_gatherpack/todo_row", column: :todo, enabled: -> { false },
      items: -> { raise "should not run" })
    register_block :off_block, "my_gatherpack_home_test/block", enabled: -> { false }

    get root_path

    assert_response :success
    assert_select "#registered-block", false
    assert_select "h1", text: /all caught up/
  end

  test "sections sort by position, then registration order" do
    MyGatherpack.sections.clear
    MyGatherpack.register_section(:late, partial: "x", column: :side, position: 30)
    MyGatherpack.register_section(:first_tie, partial: "x", column: :side, position: 10)
    MyGatherpack.register_section(:second_tie, partial: "x", column: :side, position: 10)
    MyGatherpack.register_section(:other_column, partial: "x", column: :todo, position: 1)

    assert_equal %i[first_tie second_tie late], MyGatherpack.sections_for(:side).map(&:key)
  end

  test "one person's items aren't shown to another" do
    other = create_login("Riley")
    Membership.create!(person: other.person, team: teams(:two))
    create_event("Morgan's practice", 1.day.from_now)
    create_event("Riley's practice", 1.day.from_now, team: teams(:two))
    create_announcement("For Riley's team", team: teams(:two))
    punch(@member.person, 1.hour.ago, nil)
    sign_out @member
    sign_in other

    get root_path

    assert_equal [ "Riley's practice" ], row_titles("coming_up")
    assert_select "h1", text: /\AHi Riley\./
    assert_select ".mg-status", false
    assert_includes response.body, "For Riley&#39;s team"
  end

  private

  def item(title, **attributes)
    MyGatherpack::Item.new(title: title, action: "Open", path: "/somewhere", **attributes)
  end

  def register_todos(*items)
    MyGatherpack.register_section(:test_todos, partial: "my_gatherpack/todo_row", column: :todo, items: -> { items })
  end

  def register_block(key, partial, enabled: nil)
    MyGatherpack.register_section(key, partial: partial, column: :side, position: 5, enabled: enabled)
  end

  def row_titles(column)
    css_select("[data-home-column=#{column}] .mg-row-title").map { |title| title.text.strip }
  end

  def create_event(name, start_time, team: teams(:one))
    Event.create!(name: name, start_time: start_time, end_time: start_time + 1.hour, event_type: event_types(:one), team: team)
  end

  def create_announcement(title, start: 1.hour.ago, team: teams(:one))
    Announcement.create!(title: title, content: "Details", start_time: start, end_time: 1.day.from_now, team: team)
  end

  def punch(person, start_time, end_time)
    TimeClockPunch.new(person: person, start_time: start_time, end_time: end_time, created_by: users(:one)).tap { |p| p.save!(validate: false) }
  end
end
