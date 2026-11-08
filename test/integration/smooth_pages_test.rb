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
    GatherPack::SmoothPages.refresh_on("events#show")

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
    GatherPack::SmoothPages.refresh_on("events#show")

    get event_path(@event)

    assert_select "meta[name=turbo-refresh-method][content=morph]", 1
    assert_select "meta[name=turbo-refresh-scroll][content=preserve]", 1
  end

  test "a page that has not opted in does not morph" do
    set_flag :feature_smooth_pages, true

    GatherPack::SmoothPages.refresh_on("events#show")

    get edit_event_path(@event)

    assert_response :success
    assert_select "meta[name=turbo-refresh-method]", false
  end

  test "pages that fill in later skip the preview" do
    set_flag :feature_smooth_pages, true

    [ root_path, calendar_index_path, time_clock_punches_path ].each do |path|
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
