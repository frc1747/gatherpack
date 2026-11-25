require "application_system_test_case"
require_relative "../support/order_inventory_world"

class OrderInventorySystemTest < ApplicationSystemTestCase
  include OrderInventoryWorld
  include Warden::Test::Helpers

  setup do
    # The app builds URLs for localhost; browse there so redirects stay on-host.
    Capybara.app_host = "http://localhost"
    Capybara.always_include_port = true
    @world, @stock = build_order_inventory_world
    # A phone: receiving is built to be done one-handed (spec §3.16).
    page.driver.browser.manage.window.resize_to(390, 800)
  end

  teardown do
    Capybara.app_host = nil
    Warden.test_reset!
  end

  test "receiving a delivery of packs into a bin on a phone" do
    with_both(@world, @stock) do
      line = ordered_line(@world, { description: "M4 screw", quantity: 3, unit: "pack", units_per: 100, item: @stock.screws })
      login_as(@world.requester.user, scope: :user)

      visit orders_deliveries_path(mine: 1)
      click_on "Receive", match: :first
      assert_text "Receive M4 screw"
      assert_checked_field "Track this item: put M4 screw away"
      assert_select "Put away in", selected: "Shop › Cabinet › Bin"
      assert_field "How many go into stock?", with: "300"
      assert_text "3 packs = 300 each"

      fill_in "How many came?", with: "2"
      assert_field "How many go into stock?", with: "200"
      assert_text "2 packs = 200 each"
      assert_operator find_field("How many go into stock?").native.size.height, :>=, 44
      assert_selector ".gp-form-actions input[type=submit][value='Record delivery']"
      assert_equal 0, evaluate_script("document.documentElement.scrollWidth - document.documentElement.clientWidth")
      click_on "Record delivery"

      assert_text "Recorded: M4 screw"
      assert_equal 200, @stock.screws.stock_at(@stock.bin)
      assert line.reload.partly_received?
      movement = StockMovement.newest_first.first
      assert_equal [ "received", "Parts Depot" ], [ movement.kind, movement.reason ]
    end
  end

  test "linking a line without an item while receiving it on a phone" do
    with_both(@world, @stock) do
      line = ordered_line(@world, { description: "small screws", quantity: 4 })
      login_as(@world.requester.user, scope: :user)

      visit new_orders_request_line_delivery_path(line.order_request, line)
      check "Track this item"
      fill_in "Which inventory item is it?", with: "M4"
      click_on "M4 screw"
      assert_text "This is M4 screw."
      select "Shop › Cabinet › Bin", from: "Put away in"
      click_on "Record delivery"

      assert_text "Recorded: small screws"
      assert_equal @stock.screws, line.reload.item
      assert_equal 4, @stock.screws.total_stock
    end
  end

  test "picking an item we stock fills an item on the request form" do
    with_both(@world, @stock) do
      login_as(@world.requester.user, scope: :user)

      visit new_orders_request_path
      fill_in "Pick from what we stock", with: "SCR"
      click_on "M4 screw"
      assert_text "Added M4 screw"
      assert_field "What is it?", with: "M4 screw"
      assert_field "Link", with: "https://partsdepot.example/p/SCR-4"
      assert_text "Draft saved"

      line = OrderRequest.order(:created_at).last.order_lines.first
      assert_equal [ @stock.screws, @world.preferred_vendor, "SCR-4" ], [ line.item, line.vendor, line.vendor_part_number ]
    end
  end
end
