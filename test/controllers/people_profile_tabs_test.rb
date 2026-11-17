require "test_helper"

class PeopleProfileTabsTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    host! "localhost"
    @person = people(:one)
    sign_in users(:one)
  end

  teardown do
    GatherPack::Features.unregister(:profile_tab_test)
  end

  test "an enabled feature's tab shows on the profile" do
    register_tab

    get person_path(@person)

    assert_response :success
    assert_select "a.nav-link[href=?]", statistics_person_path(@person, from: "feature"), text: "Feature Tab"
  end

  test "the tab is hidden when its feature is off" do
    feature = register_tab
    feature.define_singleton_method(:enabled?) { false }

    get person_path(@person)

    assert_response :success
    assert_select "a.nav-link", text: "Feature Tab", count: 0
  end

  test "the tab is hidden when visible: is false" do
    register_tab(visible: ->(user, person) { user.person != person })

    get person_path(@person)

    assert_response :success
    assert_select "a.nav-link", text: "Feature Tab", count: 0
  end

  test "the visible: proc gets the current user and the person" do
    seen = nil
    register_tab(visible: ->(user, person) { seen = [ user, person ] })

    get person_path(@person)

    assert_equal [ users(:one), @person ], seen
  end

  test "the tab is active on its own page" do
    register_tab

    get person_path(@person)
    assert_select "a.nav-link:not(.active)", text: "Feature Tab"

    get statistics_person_path(@person, from: "feature")
    assert_select "a.nav-link.active", text: "Feature Tab"
  end

  test "a visible: check that raises hides only that tab" do
    register_tab(
      GatherPack::Feature::ProfileTab.new(label: "Broken Tab", path: ->(person) { person_path(person) },
        visible: ->(_user, _person) { raise "boom" }),
      GatherPack::Feature::ProfileTab.new(label: "Feature Tab", path: ->(person) { recent_activity_person_path(person) })
    )

    get person_path(@person)

    assert_response :success
    assert_select "a.nav-link", text: "Broken Tab", count: 0
    assert_select "a.nav-link", text: "Feature Tab"
    assert_select "a.nav-link", text: "Overview"
  end

  private

  def register_tab(*tabs, visible: nil)
    tabs = [ GatherPack::Feature::ProfileTab.new(label: "Feature Tab",
      path: ->(person) { statistics_person_path(person, from: "feature") }, visible: visible) ] if tabs.empty?
    feature = GatherPack::Feature.new(key: :profile_tab_test, label: "Profile Tab Test", toggleable: false,
      profile_tabs: tabs)
    GatherPack::Features.register(feature)
    feature
  end
end
