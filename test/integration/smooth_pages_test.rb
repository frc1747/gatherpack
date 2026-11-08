require "test_helper"
require "support/smooth_pages_test_settings"

class SmoothPagesTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include SmoothPagesTestSettings

  setup do
    host! "localhost"
    @user = users(:one)
    @user.update_columns(admin: true)
    @event = events(:one)
    sign_in @user
  end

  test "the flag is off by default" do
    assert_equal "false", GatherPack::Features.all.find { |f| f.key == :smooth_pages }.default_enabled.to_s
  end

  test "with the flag off the page has none of it" do
    set_flag :feature_smooth_pages, false
    get event_path(@event)

    assert_response :success
    assert_select "meta[name=turbo-refresh-method]", false
    assert_select "meta[name=turbo-refresh-scroll]", false
    assert_select ".sidebar[data-turbo-permanent]", false
    assert_select ".sidebar[data-controller]", false
    assert_select ".sidebar[id]", false
    assert_select "link[href*=smooth_pages]", false

    get root_path
    assert_select "meta[name=turbo-cache-control]", false
  end

  test "an opted-in page asks for morph and kept scroll" do
    set_flag :feature_smooth_pages, true
    get event_path(@event)

    assert_select "meta[name=turbo-refresh-method][content=morph]", 1
    assert_select "meta[name=turbo-refresh-scroll][content=preserve]", 1
  end

  test "check-out leaves the list frame so it can return to the page" do
    Checkin.create!(event: @event, person: people(:two), created_by: @user.person)

    get event_path(@event)

    assert_select "turbo-frame#results a[data-turbo-method=delete][data-turbo-frame=_top]", text: "Checkout", minimum: 1
  end

  test "a page that has not opted in does not morph" do
    set_flag :feature_smooth_pages, true

    get edit_event_path(@event)

    assert_response :success
    assert_select "meta[name=turbo-refresh-method]", false
  end

  test "pages that fill in later skip the preview" do
    set_flag :feature_smooth_pages, true

    [ root_path, calendar_index_path, time_clock_punches_path, team_path(teams(:one)) ].each do |path|
      get path
      assert_response :success
      assert_select "meta[name=turbo-cache-control][content=no-preview]", 1, "expected no-preview on #{path}"
    end

    get event_path(@event)
    assert_select "meta[name=turbo-cache-control]", false
  end

  test "the sidebar is permanent and its id is a digest" do
    set_flag :feature_smooth_pages, true

    get root_path

    assert_select ".sidebar[data-turbo-permanent][data-controller='smooth-icons smooth-sidebar']", 1
    assert_match(/\Asidebar-\h{12}\z/, sidebar_id)
  end

  test "the sidebar id stays the same between pages" do
    set_flag :feature_smooth_pages, true

    get root_path
    first_id = sidebar_id
    get event_path(@event)

    assert_equal first_id, sidebar_id
  end

  test "the sidebar id changes with its menu" do
    set_flag :feature_smooth_pages, true
    set_flag :feature_badges, true

    get root_path
    first_id = sidebar_id
    set_flag :feature_badges, false
    get root_path

    assert_not_equal first_id, sidebar_id
  end

  test "the sidebar id changes with the signed-in name" do
    set_flag :feature_smooth_pages, true

    get root_path
    first_id = sidebar_id
    @user.person.update_columns(display_name: "Someone Else", first_name: "Someone", last_name: "Else")
    get root_path

    assert_not_equal first_id, sidebar_id
  end

  test "the sidebar id follows who can see each item" do
    set_flag :feature_smooth_pages, true
    item = GatherPack::Feature::NavItem.new(label: "Only Some", path: "/only-some", icon: "star")
    visible = true
    item.define_singleton_method(:visible?) { |_user| visible }
    GatherPack::Features.register(
      GatherPack::Feature.new(key: :smooth_test_item, label: "Test", toggleable: false, nav_section: "People", nav_items: [ item ])
    )

    get root_path
    first_id = sidebar_id
    visible = false
    get root_path

    assert_not_equal first_id, sidebar_id
  end

  test "the sidebar id follows registered fingerprints" do
    set_flag :feature_smooth_pages, true
    value = "before"
    GatherPack::SidebarSlots.fingerprint(:smooth_test) { value }

    get root_path
    first_id = sidebar_id
    value = "after"
    get root_path

    assert_not_equal first_id, sidebar_id
  end

  test "the sidebar id differs between people" do
    set_flag :feature_smooth_pages, true

    get root_path
    first_id = sidebar_id
    sign_out @user
    sign_in users(:two)
    get root_path

    assert_not_equal first_id, sidebar_id
  end

  test "the sidebar id changes when impersonating" do
    set_flag :feature_smooth_pages, true

    get root_path
    first_id = sidebar_id
    post impersonate_person_path(people(:two))
    get root_path

    assert_not_equal first_id, sidebar_id
  end

  private

  def sidebar_id
    css_select(".sidebar").first["id"]
  end
end
