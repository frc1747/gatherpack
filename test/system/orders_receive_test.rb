require "application_system_test_case"
require_relative "../support/orders_world"

class OrdersReceiveTest < ApplicationSystemTestCase
  include OrdersWorld
  include Warden::Test::Helpers

  setup do
    # The app builds URLs for localhost; browse there so redirects stay on-host.
    Capybara.app_host = "http://localhost"
    Capybara.always_include_port = true
    @world = build_orders_world
    # A phone: receiving is built to be done one-handed (spec §3.16).
    page.driver.browser.manage.window.resize_to(390, 800)
  end

  teardown do
    Capybara.app_host = nil
    Warden.test_reset!
  end

  def ordered_request
    order_request = approved_request(@world, lines: [ { description: "Gear", quantity: 3, price: 10 }, { description: "Belt", price: 5 } ])
    buy(@world, order_request.order_lines.to_a, vendor: @world.preferred_vendor)
    order_request.reload
  end

  test "receiving part of an item from the To receive list on a phone" do
    with_orders(@world) do
      order_request = ordered_request
      login_as(@world.requester.user, scope: :user)

      visit orders_deliveries_path(mine: 1)
      assert_text "To receive"
      assert_text "Parts Depot"
      assert_operator find_link("Receive", match: :first).native.size.height, :>=, 44

      assert_operator find_link("All I can receive").native.size.height, :>=, 44
      click_on "Receive", match: :first
      assert_text "Receive Gear"
      fill_in "How many came?", with: "2"
      select "Good", from: "How is it?"
      fill_in "Note", with: "Two of three"
      # The form ends in the standard button row (pinned while Pinned form buttons is on), not a bar of its own.
      assert_selector ".gp-form-actions input[type=submit][value='Record delivery']"
      assert_no_selector ".fixed-bottom input[type=submit]"
      click_on "Record delivery"

      assert_text "Recorded: Gear"
      assert_current_path orders_deliveries_path(mine: 1)
      assert_text "1 of 3 to come"
      assert order_request.order_lines.find_by(description: "Gear").partly_received?
    end
  end

  test "marking everything on a request received from its page on a phone" do
    with_orders(@world) do
      order_request = ordered_request
      login_as(@world.requester.user, scope: :user)

      visit orders_request_path(order_request)
      assert_text "Receiving"
      click_on "Mark all received"

      assert_text "Everything on this request is marked as here"
      assert order_request.reload.received?
    end
  end

  test "the buyer's no-record button and note field are phone sized" do
    with_orders(@world) do
      order_request = ordered_request
      login_as(@world.buyer.user, scope: :user)

      visit orders_request_path(order_request)
      assert_operator find_button("Already got it", match: :first).native.size.height, :>=, 44
      assert_operator first("input[aria-label='Where it went']").native.size.height, :>=, 44
    end
  end

  test "reporting a damaged delivery, then the buyer ordering a replacement" do
    with_orders(@world) do
      order_request = ordered_request
      login_as(@world.requester.user, scope: :user)

      visit orders_request_path(order_request)
      first(:link, "Receive").click
      fill_in "How many came?", with: "3"
      select "Damaged", from: "How is it?"
      fill_in "Note", with: "Crushed"
      click_on "Record delivery"
      assert_text "Problem with delivery"

      logout(:user)
      login_as(@world.buyer.user, scope: :user)
      visit orders_request_path(order_request)
      click_on "Order a replacement"
      assert_text "Ordering a replacement for Gear"
      assert_equal 2, order_request.order_lines.reload.count { |line| line.description == "Gear" }
    end
  end
end
