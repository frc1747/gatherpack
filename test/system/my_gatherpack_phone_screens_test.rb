require "application_system_test_case"
require "my_gatherpack_test_helper"

class MyGatherpackPhoneScreensSystemTest < ApplicationSystemTestCase
  include Devise::Test::IntegrationHelpers
  include MyGatherpackTestHelper

  # config.hosts allows localhost in test, but not Capybara's 127.0.0.1.
  setup do
    @saved_app_host = Capybara.app_host
    @saved_include_port = Capybara.always_include_port
    Capybara.app_host = "http://localhost"
    Capybara.always_include_port = true
    turn_on_my_gatherpack
    @saved_time_tracking = Settings.get(:feature_time_tracking).instance_variable_get(:@value)
    Settings[:feature_time_tracking] = "true"
    page.driver.browser.manage.window.resize_to(390, 844)
    @admin = create_login("Morgan", admin: true)
    @member = create_login("Jordan")
    @mine = TimeClockPunch.new(person: @member.person, start_time: Time.zone.parse("2026-03-02 09:00"), end_time: Time.zone.parse("2026-03-02 11:30"))
    @mine.created_by = "kiosk"
    @mine.save!
    @other = TimeClockPunch.new(person: @admin.person, start_time: Time.zone.parse("2026-03-03 09:00"), end_time: Time.zone.parse("2026-03-03 10:00"))
    @other.created_by = "kiosk"
    @other.save!
  end

  teardown do
    # The browser is shared with other system tests.
    page.driver.browser.manage.window.resize_to(1400, 1400)
    Settings.get(:feature_time_tracking).instance_variable_set(:@value, @saved_time_tracking)
    restore_my_gatherpack
    Capybara.app_host = @saved_app_host
    Capybara.always_include_port = @saved_include_port
  end

  def assert_no_sideways_scroll
    assert page.evaluate_script("document.documentElement.scrollWidth <= document.documentElement.clientWidth")
  end

  test "my hours shows the total first, then rows, with edit behind a tap" do
    sign_in @member
    visit time_clock_punches_path

    assert_selector ".mg-hours-total", text: "2.5"
    assert_selector ".mg-punch", count: 1
    assert_no_selector "table", visible: true
    assert_no_selector ".mg-punch-actions a", visible: true

    find(".mg-punch-summary").click
    assert_selector ".mg-punch-actions a", text: "Edit"
    assert_selector ".mg-punch-actions a", text: "Delete"
    assert page.evaluate_script("[...document.querySelectorAll('.mg-punch-summary, .mg-punch-actions .btn')].every(t => t.getBoundingClientRect().height >= 44)")
    assert page.evaluate_script("document.querySelector('.mg-hours-total').getBoundingClientRect().top < document.querySelector('.mg-punch').getBoundingClientRect().top")
    assert_no_sideways_scroll
  end

  test "my hours keeps the original rows and table when the punch can't be edited" do
    period = TimeClockPeriod.create!(name: "Locked", start_time: Time.zone.parse("2026-01-01"), end_time: Time.zone.parse("2026-12-31"), permission: :added_by_admin)
    @mine.created_by = "kiosk"
    @mine.update!(time_clock_period: period)
    sign_in @member
    visit time_clock_punches_path

    assert_selector ".mg-punch", count: 1
    assert_no_selector "details.mg-punch"
    assert_no_selector ".mg-punch-actions"
    assert_no_sideways_scroll
  end

  test "my hours filters sit behind a button" do
    sign_in @admin
    visit time_clock_punches_path

    assert_selector ".mg-punch", text: "Morgan Tester"
    assert_no_selector "#punch-filters", visible: true
    find(".mg-filter-toggle").click
    assert_selector "#punch-filters", visible: true
    assert_no_sideways_scroll
  end

  test "my hours with the flag off is today's table" do
    Settings[:feature_my_gatherpack] = "false"
    sign_in @member
    visit time_clock_punches_path

    assert_no_selector ".mg-hours-total"
    assert_selector "table", text: "Hours"
    assert_no_sideways_scroll
  end

  test "the calendar opens on list with a toolbar that fits" do
    sign_in @member
    visit calendar_index_path

    assert_selector ".fc-list"
    assert_toolbar_fits
    assert_no_sideways_scroll
  end

  test "the calendar fits with the flag off" do
    Settings[:feature_my_gatherpack] = "false"
    sign_in @member
    visit calendar_index_path

    assert_selector ".fc-list"
    assert_toolbar_fits
    assert_no_sideways_scroll
  end

  test "the dashboard calendar toolbar fits" do
    sign_in @member
    visit root_path

    assert_selector ".fc-list"
    assert_toolbar_fits
    assert_no_sideways_scroll
  end

  test "the dashboard calendar fits with the flag off" do
    Settings[:feature_my_gatherpack] = "false"
    sign_in @member
    visit root_path

    assert_selector ".fc-list"
    assert_toolbar_fits
    assert_no_sideways_scroll
  end

  private

  # Every toolbar button and the title sit inside the calendar's own box.
  def assert_toolbar_fits
    assert_selector ".fc-toolbar"
    assert page.evaluate_script(<<~JS)
      (() => {
        const box = document.querySelector("#calendar").getBoundingClientRect()
        return [...document.querySelectorAll("#calendar .fc-toolbar button, #calendar .fc-toolbar-title")].every(el => {
          const r = el.getBoundingClientRect()
          return r.left >= box.left - 1 && r.right <= box.right + 1
        })
      })()
    JS
  end
end
