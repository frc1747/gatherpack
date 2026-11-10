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
    @today = Time.current.beginning_of_day
    @current = TimeClockPeriod.create!(name: "Current", start_time: @today - 6.months, end_time: @today + 6.months, permission: :added_by_user)
    @past = TimeClockPeriod.create!(name: "Past", start_time: @today - 3.years, end_time: @today - 2.years, permission: :added_by_user)
    @mine = punch(@member, @today - 2.days + 9.hours, 2.5.hours, @current)
    @other = punch(@admin, @today - 1.day + 9.hours, 1.hour, @current)
  end

  def punch(login, start, length, period)
    record = TimeClockPunch.new(person: login.person, start_time: start, end_time: start + length, time_clock_period: period)
    record.created_by = "kiosk"
    record.save!
    record
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
    punch(@member, @today - 30.months + 9.hours, 4.hours, @past)
    punch(@member, @today - 4.days + 9.hours, 3.hours, nil)
    sign_in @member
    visit time_clock_punches_path

    assert_selector ".mg-hours-total", text: "Hours in Current"
    assert_selector ".mg-hours-total-value", exact_text: "2.5"
    assert_selector ".mg-punch", count: 3
    assert_no_selector "table", visible: true
    assert_no_selector ".mg-punch-actions a", visible: true

    find(".mg-punch-summary", text: "2.5").click
    assert_selector ".mg-punch-actions a", text: "Edit"
    assert_selector ".mg-punch-actions a", text: "Delete"
    assert page.evaluate_script("[...document.querySelectorAll('.mg-punch-summary, .mg-punch-actions .btn')].filter(t => t.offsetParent).every(t => t.getBoundingClientRect().height >= 44)")
    assert page.evaluate_script("document.querySelector('.mg-hours-total').getBoundingClientRect().top < document.querySelector('.mg-punch').getBoundingClientRect().top")
    assert_no_sideways_scroll
  end

  test "the total follows a selected period" do
    punch(@member, @today - 30.months + 9.hours, 4.hours, @past)
    sign_in @member
    visit time_clock_punches_path(q: { time_clock_period_id_eq: @past.id })

    assert_selector ".mg-hours-total", text: "Hours in Past"
    assert_selector ".mg-hours-total-value", exact_text: "4"
  end

  test "there is no total for several people or when no period applies" do
    sign_in @admin
    visit time_clock_punches_path
    assert_selector ".mg-punch", minimum: 2
    assert_no_selector ".mg-hours-total"

    sign_out @admin
    @current.update!(end_time: @today - 1.month)
    sign_in @member
    visit time_clock_punches_path
    assert_selector ".mg-punch", count: 1
    assert_no_selector ".mg-hours-total"
  end

  test "a row shows the year and the end date when they differ" do
    punch(@member, @today - 2.years - 3.days + 22.hours, 4.hours, @past)
    overnight = punch(@member, @today - 10.days + 22.hours, 4.hours, @current)
    sign_in @member
    visit time_clock_punches_path

    assert_selector ".mg-punch-time", text: /#{(@today - 2.years - 3.days).year}.*10:00PM – \w{3} \w{3} \d+( \d{4})?, 2:00AM/
    assert_selector ".mg-punch-time", text: /10:00PM – \w{3} \w{3} \d+( \d{4})?, 2:00AM/
    assert_no_selector ".mg-punch-time", text: /#{@mine.start_time.strftime("%b %-d")} #{@mine.start_time.year}/ if @mine.start_time.year == Time.current.year
    assert overnight.persisted?
  end

  test "a long period name stays inside the card" do
    long = TimeClockPeriod.create!(name: "Fall Outreach and Volunteer Service Hours", start_time: @today - 1.year, end_time: @today + 1.year, permission: :added_by_user)
    @mine.created_by = "kiosk"
    @mine.update!(time_clock_period: long)
    sign_in @member
    visit time_clock_punches_path

    assert_selector ".mg-punch-meta .badge", text: "Fall Outreach"
    assert page.evaluate_script(<<~JS)
      (() => {
        const card = document.querySelector(".mg-punch").getBoundingClientRect()
        const hours = document.querySelector(".mg-punch-hours").getBoundingClientRect()
        return [...document.querySelectorAll(".mg-punch-meta .badge")].every(b => {
          const r = b.getBoundingClientRect()
          return r.right <= card.right && r.right <= hours.left
        })
      })()
    JS
  end

  test "my hours reached by a Turbo visit keeps its styles" do
    sign_in @member
    visit root_path
    find(".phone-tab", text: "Hours").click

    assert_selector ".mg-hours-total"
    assert_equal "flex", page.evaluate_script("getComputedStyle(document.querySelector('.mg-hours-total')).display")
    assert_no_sideways_scroll
  end

  test "a row links to the person and the period" do
    sign_in @member
    visit time_clock_punches_path

    assert_selector ".mg-punch-summary a[href='#{person_path(@member.person)}']"
    assert_selector ".mg-punch-summary a[href='#{time_clock_period_path(@current)}']"
  end

  test "new punch stays in reach while the filters are folded" do
    sign_in @member
    visit time_clock_punches_path

    assert_selector "a", text: "New Time Clock Punch"
    assert_no_selector "input[type=search], input#q_person_display_name_i_cont", visible: true
    assert_no_selector "input[type=submit][value=Search]", visible: true
    find(".mg-filter-toggle").click
    assert_selector "input[type=submit][value=Search]"
    assert_no_sideways_scroll
  end

  test "a punch can be edited and saved from a phone" do
    sign_in @member
    visit time_clock_punches_path
    find(".mg-punch-summary", text: "2.5").click
    click_on "Edit"
    fill_in "Note", with: "Pit crew"
    find("input[type=submit], button[type=submit]").click

    assert_text "successfully updated"
    assert_equal "Pit crew", @mine.reload.note
  end

  test "a punch can be deleted from a phone" do
    sign_in @member
    visit time_clock_punches_path
    find(".mg-punch-summary", text: "2.5").click
    accept_confirm { click_on "Delete" }

    assert_no_selector ".mg-punch"
    assert_not TimeClockPunch.exists?(@mine.id)
  end

  test "the period page keeps today's table" do
    sign_in @admin
    visit time_clock_period_path(@current)

    assert_selector "table", text: "Hours"
    assert_no_selector ".mg-punch"
    assert_no_selector ".mg-hours-total"
  end

  test "at desktop width my hours is the table" do
    page.driver.browser.manage.window.resize_to(1400, 900)
    sign_in @member
    visit time_clock_punches_path

    assert_selector "table", text: "Hours"
    assert_no_selector ".mg-punch"
    assert_no_selector ".mg-hours-total"
  end

  test "my hours keeps the original rows and table when the punch can't be edited" do
    period = TimeClockPeriod.create!(name: "Locked", start_time: @today - 1.year, end_time: @today + 1.year, permission: :added_by_admin)
    @mine.created_by = "kiosk"
    @mine.update!(time_clock_period: period)
    sign_in @member
    visit time_clock_punches_path

    assert_selector ".mg-punch", count: 1
    assert_no_selector "details.mg-punch"
    assert_no_selector ".mg-punch-actions"
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

  test "calendar toolbar buttons are at least 44 px tall" do
    sign_in @member
    visit calendar_index_path

    assert_selector ".fc-toolbar button"
    assert page.evaluate_script("[...document.querySelectorAll('#calendar .fc-toolbar button')].every(b => b.getBoundingClientRect().height >= 44)")
  end

  test "the dashboard calendar keeps its one-row toolbar on a wide desktop" do
    Settings[:feature_my_gatherpack] = "false"
    page.driver.browser.manage.window.resize_to(1440, 900)
    sign_in @member
    visit root_path

    assert_selector ".fc-toolbar"
    assert_no_selector ".fc-footer-toolbar"
  end

  test "the calendar fits with the flag off" do
    Settings[:feature_my_gatherpack] = "false"
    sign_in @member
    visit calendar_index_path

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
