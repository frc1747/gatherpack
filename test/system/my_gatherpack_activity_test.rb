require "application_system_test_case"
require_relative "../support/my_gatherpack_activity_world"

class MyGatherpackActivitySystemTest < ApplicationSystemTestCase
  include Devise::Test::IntegrationHelpers
  include MyGatherpackActivityWorld

  # config.hosts allows localhost in test, but not Capybara's 127.0.0.1.
  setup do
    @saved_app_host = Capybara.app_host
    @saved_include_port = Capybara.always_include_port
    Capybara.app_host = "http://localhost"
    Capybara.always_include_port = true
    travel_to NOW
    @restore_settings = SettingsTestHelper.apply(activity_flags)
    page.driver.browser.manage.window.resize_to(390, 844)
    build_activity_world
    sign_in person(:member).user
  end

  teardown do
    # The browser is shared with other system tests.
    page.driver.browser.manage.window.resize_to(1400, 1400)
    @restore_settings&.call
    travel_back
    Capybara.app_host = @saved_app_host
    Capybara.always_include_port = @saved_include_port
  end

  test "at 390 px a member opens the page from Home and jumps to a kind of event" do
    visit root_path
    within("[data-home-section=activity]") do
      assert_text "Build: 1 event"
      click_link "See all your activity"
    end

    assert_current_path activity_path
    assert_selector "h1", text: "Your activity"
    assert_selector "[data-activity-meetings]", count: 1, text: "Meetings: 1 of 1 · 2 h"
    assert_selector "[data-activity-line]", count: 3
    assert_operator page.evaluate_script("document.documentElement.scrollWidth"), :<=, 390

    # One column: what you've done, then requirements.
    tops = page.evaluate_script("Array.from(document.querySelectorAll('[data-activity-block]')).map(b => [b.dataset.activityBlock, b.getBoundingClientRect().top, b.getBoundingClientRect().left])")
    assert_equal %w[done checklists], tops.map(&:first)
    assert_equal tops.sort_by { |_, top, _| top }, tops
    assert_equal 1, tops.map(&:last).uniq.size

    jumps = page.evaluate_script("Array.from(document.querySelectorAll('[data-activity-jump] a')).map(a => a.getBoundingClientRect().height)")
    assert jumps.any? && jumps.all? { |height| height >= 44 }, "every jump link is a 44 px target: #{jumps.inspect}"

    assert_equal 0, page.evaluate_script("window.scrollY")
    within("[data-activity-jump]") { click_link "Outreach" }
    page.document.synchronize { raise Capybara::ExpectationNotMet, "didn't scroll" unless page.evaluate_script("window.scrollY").positive? }
    within("[data-activity-kind=#{@outreach.neat_id}]") do
      assert_text "Outreach: 2 events · 6 h"
      assert_text "Food drive"
    end
  end

  test "choosing another season reloads the page with that season" do
    visit activity_path
    assert_no_selector "[data-activity-line]", text: "Spring fair"

    select "2025–26", from: "Season"

    assert_selector "[data-activity-line]", count: 1, text: "Spring fair"
    assert_current_path activity_path(season: 2025)
    assert_equal "2025", find("select[name=season]").value
  end

  test "with scripts off the Show button still shows the chosen season" do
    visit activity_path
    assert_no_button "Show"
    page.execute_script("const form = document.querySelector('.screen-filter-bar form'); form.removeAttribute('data-action'); form.removeAttribute('data-controller')")
    select "2025–26", from: "Season"
    assert_no_selector "[data-activity-line]", text: "Spring fair"

    page.execute_script("document.querySelector('.screen-filter-bar input[type=submit]').click()")

    assert_selector "[data-activity-line]", count: 1, text: "Spring fair"
    assert_current_path activity_path(season: 2025)
  end
end
