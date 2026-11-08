require "test_helper"

class SidebarSlotsHelperTest < ActionView::TestCase
  helper NavHelper

  setup do
    @saved_slots = GatherPack::SidebarSlots.instance_variable_get(:@slots).dup
    @saved_root_attributes = GatherPack::SidebarSlots.instance_variable_get(:@root_attributes).dup
    @saved_fingerprints = GatherPack::SidebarSlots.instance_variable_get(:@fingerprints).dup
    GatherPack::SidebarSlots.reset!
    @user = users(:one)
    @user.person ||= people(:one)
    view.extend(Module.new do
      attr_accessor :test_user, :test_admin
      def current_user = test_user
      def true_user = test_user
      def admin? = test_admin
    end)
    view.test_user = @user
    view.test_admin = true
    view.lookup_context.prepend_view_paths([ Rails.root.join("test/fixtures/views").to_s ])
    request.path = "/"
  end

  teardown do
    GatherPack::SidebarSlots.instance_variable_set(:@slots, @saved_slots)
    GatherPack::SidebarSlots.instance_variable_set(:@root_attributes, @saved_root_attributes)
    GatherPack::SidebarSlots.instance_variable_set(:@fingerprints, @saved_fingerprints)
  end

  def wrapped_sidebar
    Nokogiri::HTML5.fragment(view.sidebar_with_root_attributes { view.render(partial: "layouts/sidebar") })
  end

  def render_sidebar
    render(partial: "layouts/sidebar")
  end

  def render_baseline
    render(inline: file_fixture("sidebar_before.html.erb").read)
  end

  test "without registrations the sidebar is identical to the one before slots" do
    assert_equal render_baseline, render_sidebar
  end

  test "slots render above the footer in position order" do
    GatherPack::SidebarSlots.register(:late, partial: "sidebar_slots_test/late", position: 20)
    GatherPack::SidebarSlots.register(:early, partial: "sidebar_slots_test/early", position: 10)

    html = render_sidebar

    assert_operator html.index("early slot"), :<, html.index("late slot")
    assert_operator html.index("late slot"), :<, html.index("<footer")
  end

  test "slots with the same position keep registration order" do
    GatherPack::SidebarSlots.register(:b, partial: "sidebar_slots_test/late", position: 10)
    GatherPack::SidebarSlots.register(:a, partial: "sidebar_slots_test/early", position: 10)

    assert_equal %i[b a], GatherPack::SidebarSlots.slots_for(view).map(&:key)
  end

  test "a slot is hidden when visible returns false" do
    GatherPack::SidebarSlots.register(:hidden, partial: "sidebar_slots_test/early", visible: ->(_view) { false })
    GatherPack::SidebarSlots.register(:shown, partial: "sidebar_slots_test/late", visible: ->(_view) { true })

    html = render_sidebar

    assert_no_match "early slot", html
    assert_match "late slot", html
  end

  test "visible runs in the view context" do
    GatherPack::SidebarSlots.register(:admins, partial: "sidebar_slots_test/early", visible: ->(view) { view.admin? })

    assert_match "early slot", render_sidebar
    view.test_admin = false
    assert_no_match "early slot", render_sidebar
  end

  test "registering a key again replaces it" do
    GatherPack::SidebarSlots.register(:one, partial: "sidebar_slots_test/early")
    GatherPack::SidebarSlots.register(:one, partial: "sidebar_slots_test/late")

    html = render_sidebar

    assert_no_match "early slot", html
    assert_match "late slot", html
  end

  test "root attributes from several registrations merge" do
    GatherPack::SidebarSlots.root_attributes(:ids) { |_view| { id: "sidebar-abc", data: { turbo_permanent: true } } }
    GatherPack::SidebarSlots.root_attributes(:more) { |_view| { data: { controller: "sidebar" }, class: "ignored" } }

    root = wrapped_sidebar.at_css("div[style='display: contents']")

    assert_equal "sidebar-abc", root["id"]
    assert_equal "true", root["data-turbo-permanent"]
    assert_equal "sidebar", root["data-controller"]
    assert_nil root["class"]
    assert root.at_css("> div.sidebar"), "expected the sidebar inside the wrapper"
  end

  test "with no root attributes the sidebar has no wrapper" do
    assert_nil wrapped_sidebar.at_css("div[style='display: contents']")
  end

  test "root attributes run in the view context" do
    GatherPack::SidebarSlots.root_attributes(:who) { |view| { data: { admin: view.admin? } } }

    assert_equal "true", wrapped_sidebar.at_css("div[style='display: contents']")["data-admin"]
  end

  test "fingerprints run in the view context and re-registering replaces one" do
    GatherPack::SidebarSlots.fingerprint(:first) { admin? }
    GatherPack::SidebarSlots.fingerprint(:second) { "old" }
    GatherPack::SidebarSlots.fingerprint(:second) { "new" }

    assert_equal [ true, "new" ], GatherPack::SidebarSlots.fingerprints_for(view)
  end
end
