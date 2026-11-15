require "application_system_test_case"
require "support/orders_world"

class OrdersApproveTest < ApplicationSystemTestCase
  include Devise::Test::IntegrationHelpers
  include OrdersWorld

  # config.hosts allows localhost in test, but not Capybara's 127.0.0.1.
  setup do
    @saved_app_host = Capybara.app_host
    @saved_include_port = Capybara.always_include_port
    Capybara.app_host = "http://localhost"
    Capybara.always_include_port = true
    page.driver.browser.manage.window.resize_to(390, 844)
    @world = build_orders_world
  end

  teardown do
    # The browser is shared with other system tests.
    page.driver.browser.manage.window.resize_to(1400, 1400)
    Capybara.app_host = @saved_app_host
    Capybara.always_include_port = @saved_include_port
  end

  test "at 390 px an approver ticks the restriction, comments and approves from the bar at the bottom" do
    with_orders(@world) do
      grant = FundingSource.create!(team: @world.robotics, name: "Parts grant", kind: :restricted,
        restriction: "Robot parts only", amount_cents: 50_000)
      order_request = submitted_request(@world, title: "Drive wheels", funding_source: grant,
        lines: [ { description: "Wheel", quantity: 4, price: 12, vendor_id: @world.preferred_vendor.id } ])
      sign_in @world.mentor.user

      visit orders_approvals_path
      # Turbo visits keep the window, so the mark survives unless a page
      # forces a full reload (which also loses the flash).
      execute_script("window.sameWindow = true")
      click_link "Drive wheels"

      assert_text "Robot parts only"
      assert evaluate_script("window.sameWindow === true"), "opening the request reloaded the page"
      assert_text "Left after this request"
      bar = find(".orders-decision-bar")
      assert_equal "fixed", evaluate_script("getComputedStyle(document.querySelector('.orders-decision-bar')).position")
      assert_in_delta evaluate_script("window.innerHeight"),
        evaluate_script("document.querySelector('.orders-decision-bar').getBoundingClientRect().bottom"), 1
      assert_operator evaluate_script("document.querySelector('.orders-decision-bar button[value=approved]').getBoundingClientRect().height"), :>=, 44
      assert_operator evaluate_script("document.documentElement.scrollWidth"), :<=, evaluate_script("window.innerWidth")

      # Approve is held back by the browser until the tick is given.
      within(bar) { click_button "Approve" }
      assert order_request.reload.submitted?

      within(bar) do
        check "This request fits the restriction of Parts grant"
        fill_in "Comment", with: "Good choice"
        click_button "Approve"
      end

      assert_text "Approved: Drive wheels"
      assert evaluate_script("window.sameWindow === true"), "deciding reloaded the page"
      assert_text "Nothing is waiting for you to approve."
      assert order_request.reload.approved?
      assert_equal "Good choice", order_request.events.last.comment
    end
  end
end
