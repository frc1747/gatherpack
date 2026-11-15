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

  test "at 390 px a member opens the page from Home and filters History" do
    visit root_path
    within("[data-home-section=activity]") do
      assert_text "Build: 1 event"
      click_link "See all your activity →"
    end

    assert_current_path activity_path
    assert_selector "h1", text: "Your activity"
    assert_selector "[data-activity-entry]", count: 5
    assert_operator page.evaluate_script("document.documentElement.scrollWidth"), :<=, 390

    # One column, in the spec's order.
    tops = page.evaluate_script("Array.from(document.querySelectorAll('[data-activity-block]')).map(b => [b.dataset.activityBlock, b.getBoundingClientRect().top, b.getBoundingClientRect().left])")
    assert_equal %w[totals kinds history checklists], tops.map(&:first)
    assert_equal tops.sort_by { |_, top, _| top }, tops
    assert_equal 1, tops.map(&:last).uniq.size

    rows = page.evaluate_script("Array.from(document.querySelectorAll('[data-activity-kind]')).map(r => r.getBoundingClientRect().height)")
    assert rows.all? { |height| height >= 44 }, "every kind row is a 44 px target: #{rows.inspect}"

    find("[data-activity-kind=#{@build.neat_id}]").click

    assert_selector "[data-activity-entry]", count: 1
    assert_selector "[data-activity-entry]", text: "Build day"
    assert_selector "#history .mg-heading", text: /History · Build/i

    click_link "Show all"
    assert_selector "[data-activity-entry]", count: 5
  end
end
