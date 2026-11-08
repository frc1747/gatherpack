require "application_system_test_case"
require "support/smooth_pages_test_settings"

class SmoothPagesSystemTest < ApplicationSystemTestCase
  include Devise::Test::IntegrationHelpers
  include SmoothPagesTestSettings

  ICONS = "svg.svg-inline--fa".freeze

  setup do
    # The test environment only allows these hosts, and not Capybara's 127.0.0.1.
    @original_app_host = Capybara.app_host
    @original_include_port = Capybara.always_include_port
    Capybara.app_host = "http://localhost"
    Capybara.always_include_port = true
    page.current_window.resize_to(1400, 1400)

    @user = users(:one)
    @user.update_columns(admin: true)
    @event = events(:one)
    set_flag :feature_smooth_pages, true
    sign_in @user
  end

  teardown do
    Capybara.app_host = @original_app_host
    Capybara.always_include_port = @original_include_port
  end

  # Morph

  test "checking someone out keeps the scroll position and updates the page" do
    checkins = check_in_many_people
    open_event

    place = center_on_checkout(checkins.first)
    assert_operator place, :>, 0
    mark_icons
    check_out checkins.first

    assert_render "morph"
    assert_no_selector "##{dom_id(checkins.first)}"
    assert_in_delta place, scroll_y, 1
    assert_text "Checkins (#{@event.checkins.count})"
  end

  test "a morph leaves icons alone" do
    checkins = check_in_many_people
    open_event

    before = mark_icons
    check_out checkins.first

    assert_render "morph"
    settle
    assert_equal before, count_marked_icons
    assert_no_selector "i.fa-solid", visible: :all
  end

  test "a normal visit does not wait for icons" do
    open_event
    spy_on_icon_conversion

    click_link "Dashboard"

    assert_render "replace"
    assert_equal 0, page.evaluate_script("window.__conversions")
  end

  test "the morph still finishes when Font Awesome is missing" do
    checkins = check_in_many_people
    open_event

    page.execute_script("window.FontAwesome = undefined")
    check_out checkins.first

    assert_render "morph"
    assert_no_selector "##{dom_id(checkins.first)}"
  end

  test "the morph still finishes when icon conversion fails" do
    checkins = check_in_many_people
    open_event

    page.execute_script("window.FontAwesome.dom.i2svg = () => Promise.reject(new Error('nope'))")
    check_out checkins.first

    assert_render "morph"
    assert_no_selector "##{dom_id(checkins.first)}"
  end

  test "with the flag off check-out only updates the list frame" do
    set_flag :feature_smooth_pages, false
    checkins = check_in_many_people
    open_event watch_only: true
    assert_no_selector "##{dom_id(checkins.first)} a[data-turbo-frame]"

    check_out checkins.first

    assert_no_selector "##{dom_id(checkins.first)}"
    wait_for_script "window.__frameRenders > 0"
    assert_operator page.evaluate_script("window.__frameRenders"), :>=, 1
    assert_empty page.evaluate_script("window.__renders")
  end

  test "hovering Checkout requests nothing" do
    checkins = check_in_many_people
    open_event
    center_on_checkout(checkins.first)
    watch_prefetches

    find("##{dom_id(checkins.first)} a", text: "Checkout").hover
    sleep 0.4

    assert_equal 0, page.evaluate_script("window.__prefetches")
    assert Checkin.exists?(checkins.first.id)

    # Shows the watch above can see a prefetch.
    find(".sidebar a", text: "Teams").hover
    sleep 0.4
    assert_equal 1, page.evaluate_script("window.__prefetches")
  end

  test "calendars still draw" do
    visit root_path
    assert_selector "#calendar.fc", wait: 10

    visit calendar_index_path
    assert_selector "#calendar.fc .fc-daygrid", wait: 10
  end

  test "a calendar keeps its space while it loads" do
    visit root_path
    assert_selector "#calendar.fc", wait: 10

    height = page.evaluate_script("document.querySelector('[data-controller=calendar]').getBoundingClientRect().height")
    root_font = page.evaluate_script("parseFloat(getComputedStyle(document.documentElement).fontSize)")

    assert_operator height, :>=, 28 * root_font - 1
  end

  # Sidebar

  test "the sidebar survives a visit" do
    visit root_path
    mark_sidebar

    click_link "Teams"

    assert_current_path teams_path
    assert sidebar_marked?, "expected the same sidebar element after a visit"
    assert_equal 1, page.all(".sidebar", visible: :all).size
  end

  test "the sidebar survives a morph" do
    checkins = check_in_many_people
    open_event
    mark_sidebar

    check_out checkins.first

    assert_render "morph"
    assert sidebar_marked?
    assert_equal 1, page.all(".sidebar", visible: :all).size
  end

  test "the sidebar is replaced after starting impersonation" do
    visit person_path(people(:two))
    mark_sidebar
    first_id = sidebar_id

    click_link "Impersonate"

    assert_selector ".impersonator-label", text: /impersonating/i, wait: 10
    assert_not sidebar_marked?
    assert_not_equal first_id, sidebar_id
  end

  test "the sidebar is replaced when its items change" do
    set_flag :feature_badges, true
    visit root_path
    assert_selector ".sidebar a", text: "Badges", visible: :all
    mark_sidebar

    set_flag :feature_badges, false
    click_link "Teams"

    assert_current_path teams_path
    assert_no_selector ".sidebar a", text: "Badges", visible: :all
    assert_not sidebar_marked?
  end

  test "a morph that changes the menu leaves one sidebar" do
    set_flag :feature_badges, true
    checkins = check_in_many_people
    open_event
    mark_sidebar

    set_flag :feature_badges, false
    check_out checkins.first

    assert_render "morph"
    assert_equal 1, page.all(".sidebar", visible: :all).size
    assert_no_selector ".sidebar a", text: "Badges", visible: :all
  end

  test "the active link follows the page" do
    visit root_path
    assert_selector ".sidebar a.active", text: "Dashboard"

    click_link "Teams"

    assert_selector ".sidebar a.active", text: "Teams"
    assert_no_selector ".sidebar a.active", text: "Dashboard"
  end

  test "the active link uses the server's special cases" do
    visit root_path

    find(".sidebar a", text: "Teams").click
    assert_current_path teams_path
    page.execute_script("window.Turbo.visit(#{event_path(@event).to_json})")

    assert_current_path event_path(@event)
    assert_selector ".sidebar a.active", text: "Calendar"
    assert_no_selector ".sidebar a.active", text: "Teams"
  end

  test "the active link is right after going back" do
    visit root_path
    click_link "Teams"
    assert_selector ".sidebar a.active", text: "Teams"

    page.go_back

    assert_current_path root_path
    assert_selector ".sidebar a.active", text: "Dashboard"
    assert_no_selector ".sidebar a.active", text: "Teams"
  end

  test "the off-canvas closes on a phone" do
    use_phone_width
    visit root_path
    open_offcanvas

    find("#sidebarMenu a", text: "Teams").click

    assert_current_path teams_path
    assert_no_selector "#sidebarMenu.show", visible: :all, wait: 5
    assert_no_selector ".offcanvas-backdrop", visible: :all, wait: 5
    assert_equal "", page.evaluate_script("document.body.style.overflow")
  end

  test "the off-canvas closes when going back on a phone" do
    use_phone_width
    visit root_path
    open_offcanvas
    find("#sidebarMenu a", text: "Teams").click
    assert_current_path teams_path
    assert_no_selector "#sidebarMenu.show", visible: :all, wait: 5
    open_offcanvas

    page.go_back

    assert_current_path root_path
    assert_no_selector "#sidebarMenu.show", visible: :all, wait: 5
    assert_no_selector ".offcanvas-backdrop", visible: :all, wait: 5
  end

  test "the sidebar keeps its scroll position between pages" do
    use_phone_width
    visit root_path
    open_offcanvas
    page.execute_script("document.querySelector('.sidebar .offcanvas-body').scrollTop = 120")
    assert_equal 120, sidebar_scroll_top

    find("#sidebarMenu a", text: "Teams").click

    assert_current_path teams_path
    assert_no_selector "#sidebarMenu.show", visible: :all, wait: 5
    open_offcanvas
    assert_equal 120, sidebar_scroll_top
  end

  private

  def dom_id(record)
    ActionView::RecordIdentifier.dom_id(record)
  end

  # With the fixture's check-in, 20 here leaves the list at four rows of six
  # before and after one check-out, so the page can still reach the old position.
  def check_in_many_people(count = 20)
    Array.new(count) do |index|
      person = Person.create!(first_name: "Guest", last_name: "Number#{index}", display_name: "Guest Number#{index}", gender: "F", shirt_size: "M")
      Checkin.create!(event: @event, person: person, created_by: @user.person)
    end
  end

  def open_event(watch_only: false)
    page.current_window.resize_to(1200, 600)
    visit event_path(@event)
    assert_selector ICONS, minimum: 3, wait: 15
    assert_selector "[data-controller~='smooth-icons']" unless watch_only
    watch_renders
  end

  def watch_renders
    page.execute_script(<<~JS)
      window.__renders = []
      window.__frameRenders = 0
      document.addEventListener("turbo:render", event => window.__renders.push(event.detail.renderMethod))
      document.addEventListener("turbo:frame-render", () => window.__frameRenders++)
    JS
  end

  def assert_render(method)
    script = "window.__renders[window.__renders.length - 1]"
    wait_for_script "#{script} === #{method.to_json}"

    assert_equal method, page.evaluate_script(script)
  end

  def wait_for_script(condition)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 15
    sleep 0.05 until page.evaluate_script(condition) || Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
  end

  # Font Awesome swaps any stray <i> on its next mutation pass.
  def settle
    sleep 0.5
  end

  def scroll_y
    page.evaluate_script("window.scrollY")
  end

  def center_on_checkout(checkin)
    link = find("##{dom_id(checkin)} a", text: "Checkout")
    link.execute_script("document.documentElement.style.scrollBehavior = 'auto'; this.scrollIntoView({ block: 'center' })")
    scroll_y
  end

  def check_out(checkin)
    link = find("##{dom_id(checkin)} a", text: "Checkout")
    accept_confirm { link.click }
  end

  def watch_prefetches
    page.execute_script(<<~JS)
      window.__prefetches = 0
      document.addEventListener("turbo:before-prefetch", () => window.__prefetches++)
    JS
  end

  def mark_icons
    page.evaluate_script(<<~JS)
      (() => {
        const icons = [...document.querySelectorAll("#{ICONS}")]
        icons.forEach(icon => { icon.__marker = true })
        return icons.length
      })()
    JS
  end

  def count_marked_icons
    page.evaluate_script(%([...document.querySelectorAll("#{ICONS}")].filter(icon => icon.__marker).length))
  end

  def spy_on_icon_conversion
    page.execute_script(<<~JS)
      window.__conversions = 0
      const original = window.FontAwesome.dom.i2svg
      window.FontAwesome.dom.i2svg = (...args) => { window.__conversions++; return original(...args) }
    JS
  end

  def mark_sidebar
    page.execute_script("document.querySelector('.sidebar').__marker = true")
  end

  def sidebar_marked?
    page.evaluate_script("document.querySelector('.sidebar').__marker === true")
  end

  def sidebar_id
    page.evaluate_script("document.querySelector('.sidebar').id")
  end

  def sidebar_scroll_top
    page.evaluate_script("document.querySelector('.sidebar .offcanvas-body').scrollTop")
  end

  def use_phone_width
    page.current_window.resize_to(420, 500)
  end

  def open_offcanvas
    assert_selector "[data-controller~='smooth-sidebar']", visible: :all
    page.execute_script("window.bootstrap.Offcanvas.getOrCreateInstance(document.querySelector('#sidebarMenu')).show()")
    assert_selector "#sidebarMenu.show", wait: 5
    sleep 0.4
  end
end
