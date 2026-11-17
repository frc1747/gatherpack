require "application_system_test_case"
require "support/orders_world"

class OrdersPurchasesTest < ApplicationSystemTestCase
  include Devise::Test::IntegrationHelpers
  include OrdersWorld

  setup do
    # The app builds URLs for localhost; browse there so redirects stay on-host.
    Capybara.app_host = "http://localhost"
    Capybara.always_include_port = true
    @world = build_orders_world
    @restore = SettingsTestHelper.apply(orders_settings(@world, orders_price_tolerance: "10%, 25"))
    Orders::Current.reset
  end

  teardown do
    Capybara.app_host = nil
    @restore&.call
    Orders::Current.reset
  end

  test "a buyer records one purchase for items from two requests" do
    first = approved_request(@world, title: "Drive gears", lines: [ { description: "Gear", price: 10, vendor_id: @world.preferred_vendor.id } ])
    second = approved_request(@world, title: "Belts", by: @world.teammate,
      lines: [ { description: "Belt", price: 20, vendor_id: @world.preferred_vendor.id } ])
    gear = first.order_lines.first
    belt = second.order_lines.first
    receipt = Rails.root.join("tmp", "receipt-#{SecureRandom.hex(4)}.pdf")
    File.write(receipt, "%PDF-1.4 receipt")

    sign_in @world.buyer.user
    visit to_buy_orders_purchases_path

    check "buy_#{gear.id}"
    check "buy_#{belt.id}"
    click_on "Record purchase"

    assert_text "Record purchase"
    fill_in "price_#{gear.id}", with: "11.50"
    fill_in "Order number", with: "PD-2041"
    fill_in "Shipping", with: "6"
    select "Team card", from: "Paid with"
    attach_file "Receipts", receipt
    click_on "Record purchase"

    assert_text "Purchase recorded."
    assert_text "Order from Parts Depot"
    within "#purchase_lines" do
      assert_text "Gear"
      assert_text "Belt"
      assert_text "$11.50"
    end
    assert_text "$37.50"

    purchase = Purchase.last
    assert_equal "PD-2041", purchase.vendor_order_number
    assert purchase.receipts.attached?
    assert gear.reload.ordered?
    assert belt.reload.ordered?
    assert_equal purchase, belt.purchase

    visit orders_request_path(first)
    within "#order_request_purchases" do
      assert_text "Parts Depot"
      assert_text "Ordered"
    end
  ensure
    FileUtils.rm_f(receipt) if receipt
  end

  test "a price past the tolerance sends the item back for re-approval" do
    order_request = approved_request(@world, title: "Motor", lines: [ { description: "Motor", price: 100, vendor_id: @world.preferred_vendor.id } ])
    line = order_request.order_lines.first

    sign_in @world.buyer.user
    visit to_buy_orders_purchases_path
    check "buy_#{line.id}"
    click_on "Record purchase"
    fill_in "price_#{line.id}", with: "200"
    click_on "Record purchase"

    assert_text "1 item costs more than was approved, so it needs re-approval."
    assert_text "Needs re-approval"
    assert line.reload.needs_reapproval?

    visit orders_request_path(order_request)
    assert_text "1 needs re-approval"
  end

  test "on a phone, the buyer's controls on the request page are at least 44 px tall" do
    order_request = approved_request(@world, title: "Gears", lines: [ { description: "Gear", price: 10, quantity: 3 } ])

    sign_in @world.buyer.user
    page.driver.browser.manage.window.resize_to(390, 844)
    visit orders_request_path(order_request)
    find("#buyer_line_actions > summary").click
    find("#buyer_line_actions .orders-line-actions > summary").click

    heights = page.evaluate_script(<<~JS)
      Array.from(document.querySelectorAll("#order_request_purchases summary, #order_request_purchases .btn, #order_request_purchases input"))
        .filter((el) => el.offsetParent !== null)
        .map((el) => el.getBoundingClientRect().height)
    JS
    assert_operator heights.size, :>=, 6
    assert heights.all? { |height| height >= 44 }, "controls shorter than 44 px: #{heights.inspect}"
  ensure
    page.driver.browser.manage.window.resize_to(1400, 1400)
  end
end
