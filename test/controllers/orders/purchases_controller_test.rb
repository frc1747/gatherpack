require "test_helper"
require "support/orders_world"

class Orders::PurchasesControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include OrdersWorld

  setup { @world = build_orders_world }

  test "To buy groups items by vendor, Vendor not chosen first, then by the oldest needed-by" do
    with_orders(@world) do
      approved_request(@world, title: "Later", needed_by: Date.current + 20,
        lines: [ { description: "Barn bolts", price: 5, vendor_id: @world.other_vendor.id } ])
      approved_request(@world, title: "Sooner", needed_by: Date.current + 2,
        lines: [ { description: "Depot gears", price: 5, vendor_id: @world.preferred_vendor.id } ])
      approved_request(@world, title: "Unsure", lines: [ { description: "Mystery part", price: 5 } ])
      approved_request(@world, by: @world.outsider, team: @world.art, lines: [ { description: "Paint", price: 5 } ])
      sign_in @world.buyer.user

      get to_buy_orders_purchases_url
      assert_response :success
      groups = css_select("h2").map { |heading| heading.text.squish }
      assert_equal [ "Vendor not chosen", "Parts Depot Preferred", "Hardware Barn" ], groups
      assert_select "#vendor_not_chosen", text: /Mystery part/
      assert_no_match "Paint", response.body
    end
  end

  test "To buy is for buyers only" do
    with_orders(@world) do
      sign_in @world.requester.user

      get to_buy_orders_purchases_url
      assert_redirected_to root_url
      assert_equal "You are not allowed to do that", flash[:notice]
    end
  end

  test "ticking items from two vendors is refused" do
    with_orders(@world) do
      first = approved_request(@world, lines: [ { description: "A", price: 5, vendor_id: @world.preferred_vendor.id } ])
      second = approved_request(@world, lines: [ { description: "B", price: 5, vendor_id: @world.other_vendor.id } ])
      sign_in @world.buyer.user

      get new_orders_purchase_url(line_ids: [ first.order_lines.first.id, second.order_lines.first.id ]),
        headers: { "HTTP_REFERER" => to_buy_orders_purchases_url }
      assert_redirected_to to_buy_orders_purchases_url
      assert_equal "Tick items from one vendor.", flash[:alert]
    end
  end

  test "recording a purchase across two requests orders their items with the actual prices" do
    with_orders(@world) do
      first = approved_request(@world, lines: [ { description: "Gear", price: 10, vendor_id: @world.preferred_vendor.id } ])
      second = approved_request(@world, by: @world.teammate,
        lines: [ { description: "Belt", price: 20, vendor_id: @world.preferred_vendor.id } ])
      gear = first.order_lines.first
      belt = second.order_lines.first
      sign_in @world.buyer.user

      get new_orders_purchase_url(line_ids: [ gear.id, belt.id ])
      assert_response :success
      assert_select "#vendor_prompt", false
      assert_select "input[name='prices[#{gear.id}]'][value='10.00']"

      receipt = Rack::Test::UploadedFile.new(StringIO.new("%PDF-1.4 receipt"), "application/pdf", original_filename: "receipt.pdf")
      post orders_purchases_url, params: {
        line_ids: [ gear.id, belt.id ],
        prices: { gear.id => "11.00", belt.id => "" },
        purchase: { vendor_order_number: "A-100", ordered_on: Date.current.iso8601, shipping: "6.00", tax: "",
                    paid_with: "Team card", expected_on: (Date.current + 5).iso8601,
                    tracking_url: "https://track.example/1", receipts: [ receipt ] }
      }

      purchase = Purchase.order(:created_at).last
      assert_redirected_to orders_purchase_url(purchase)
      assert_equal "Purchase recorded.", flash[:notice]
      assert_equal @world.preferred_vendor, purchase.vendor
      assert_equal "A-100", purchase.vendor_order_number
      assert_equal 600, purchase.shipping_cents
      assert_equal 0, purchase.tax_cents
      assert_nil purchase.reimburse_to
      assert_equal [ "receipt.pdf" ], purchase.receipts.map { |file| file.filename.to_s }
      assert_equal 1100, gear.reload.actual_unit_price_cents
      assert_equal 2000, belt.reload.actual_unit_price_cents
      assert gear.ordered?
      assert belt.ordered?
      assert first.reload.ordering?
      assert second.reload.ordering?
      assert_equal [ "purchased" ], first.events.where(order_line: gear).pluck(:action)
    end
  end

  test "a Not sure item takes the vendor the buyer names" do
    with_orders(@world) do
      order_request = approved_request(@world, lines: [ { description: "Mystery part", price: 5 } ])
      line = order_request.order_lines.first
      sign_in @world.buyer.user

      get new_orders_purchase_url(line_ids: [ line.id ])
      assert_select "#vendor_prompt select[name='purchase[vendor_id]']"

      post orders_purchases_url, params: { line_ids: [ line.id ], purchase: { vendor_id: @world.other_vendor.id, paid_with: "Team card" } }

      assert_redirected_to orders_purchase_url(Purchase.last)
      assert_equal @world.other_vendor, line.reload.vendor
      assert_equal @world.other_vendor, Purchase.last.vendor
    end
  end

  test "a Not sure item with no vendor named shows the form again" do
    with_orders(@world) do
      line = approved_request(@world, lines: [ { description: "Mystery part", price: 5 } ]).order_lines.first
      sign_in @world.buyer.user

      post orders_purchases_url, params: { line_ids: [ line.id ], purchase: { paid_with: "Team card" } }

      assert_response :unprocessable_content
      assert_match "another store&#39;s name is needed", response.body
      assert line.reload.approved?
      assert_equal 0, Purchase.count
    end
  end

  test "paying with a card to reimburse records who to pay back" do
    with_orders(@world) do
      line = approved_request(@world, lines: [ { description: "Gear", price: 5, vendor_id: @world.preferred_vendor.id } ]).order_lines.first
      sign_in @world.buyer.user

      post orders_purchases_url, params: { line_ids: [ line.id ], purchase: { paid_with: "Personal card — reimburse" } }

      assert_equal @world.buyer, Purchase.last.reimburse_to
      assert Purchase.last.reimburse?
    end
  end

  test "a price past the tolerance sends the item for re-approval" do
    with_orders(@world, orders_price_tolerance: "10%, 25") do
      order_request = approved_request(@world, lines: [ { description: "Motor", price: 100, vendor_id: @world.preferred_vendor.id } ])
      line = order_request.order_lines.first
      sign_in @world.buyer.user

      post orders_purchases_url, params: { line_ids: [ line.id ], prices: { line.id => "200" }, purchase: { paid_with: "Team card" } }

      assert_match "needs re-approval", flash[:notice]
      assert line.reload.needs_reapproval?
      assert order_request.reload.needs_reapproval?
      assert_includes Orders::WaitingOn.new(@world.mentor).to_reapprove, order_request
    end
  end

  test "someone who sees a purchase through a request sees only their items, the vendor, date and status" do
    with_orders(@world) do
      mine = approved_request(@world, lines: [ { description: "My gear", price: 10, vendor_id: @world.preferred_vendor.id } ])
      theirs = approved_request(@world, by: @world.builder, team: @world.build,
        lines: [ { description: "Their belt", price: 20, vendor_id: @world.preferred_vendor.id } ])
      purchase = buy(@world, mine.order_lines + theirs.order_lines, vendor: @world.preferred_vendor, vendor_order_number: "SECRET-1")

      sign_in @world.requester.user
      get orders_purchase_url(purchase)
      assert_response :success
      assert_match "My gear", response.body
      assert_no_match "Their belt", response.body
      assert_no_match "SECRET-1", response.body
      assert_no_match "Buyer Example", response.body
      assert_match "Parts Depot", response.body

      sign_in @world.buyer.user
      get orders_purchase_url(purchase)
      assert_match "Their belt", response.body
      assert_match "SECRET-1", response.body
    end
  end

  test "a purchase is refused to someone who can see none of its requests" do
    with_orders(@world) do
      purchase = buy(@world, approved_request(@world).order_lines.to_a)
      sign_in @world.outsider.user

      get orders_purchase_url(purchase)
      assert_response :not_found

      sign_in @world.outsider.user
      get orders_purchases_url
      assert_response :success
      assert_select ".list-group-item", false
    end
  end

  test "the buyer edits the order and a new expected date goes on the timeline" do
    with_orders(@world) do
      order_request = approved_request(@world)
      purchase = buy(@world, order_request.order_lines.to_a)
      sign_in @world.buyer.user

      get edit_orders_purchase_url(purchase)
      assert_response :success

      patch orders_purchase_url(purchase), params: { purchase: { expected_on: "2030-01-15", tracking_url: "https://track.example/2" } }

      assert_redirected_to orders_purchase_url(purchase)
      assert_equal Date.new(2030, 1, 15), purchase.reload.expected_on
      event = order_request.events.where(action: "edited").last
      assert_equal [ nil, "2030-01-15" ], event.field_changes["expected_on"]
    end
  end

  test "people who only see a purchase through a request can't edit it" do
    with_orders(@world) do
      purchase = buy(@world, approved_request(@world).order_lines.to_a)
      sign_in @world.requester.user

      patch orders_purchase_url(purchase), params: { purchase: { vendor_order_number: "X" } }
      assert_equal "You are not allowed to do that", flash[:notice]
      assert_nil purchase.reload.vendor_order_number
    end
  end

  test "a buyer turns an Other store name into a vendor" do
    with_orders(@world) do
      order_request = approved_request(@world, lines: [ { description: "Glue", price: 3, other_vendor_name: "Corner Store" } ])
      purchase = buy(@world, order_request.order_lines.to_a)
      sign_in @world.buyer.user

      get orders_purchase_url(purchase)
      assert_select "form[action='#{make_vendor_orders_purchase_path(purchase)}']"

      assert_difference -> { Vendor.count }, 1 do
        post make_vendor_orders_purchase_url(purchase)
      end
      vendor = Vendor.find_by!(name: "Corner Store")
      assert_equal vendor, purchase.reload.vendor
      assert_nil purchase.other_vendor_name
      assert_equal vendor, order_request.order_lines.first.reload.vendor
      assert_equal [ "Corner Store", "Corner Store" ], order_request.events.where(action: "edited").last.field_changes["vendor"]

      post make_vendor_orders_purchase_url(purchase)
      assert_equal "This order already has a vendor.", flash[:alert]
    end
  end

  test "the request page shows where its items were ordered" do
    with_orders(@world) do
      order_request = approved_request(@world, lines: [ { description: "Gear", price: 10, vendor_id: @world.preferred_vendor.id } ])
      buy(@world, order_request.order_lines.to_a, vendor: @world.preferred_vendor)
      sign_in @world.requester.user

      get orders_request_url(order_request)
      assert_select "#order_request_purchases", text: /Parts Depot/
      assert_select "#buyer_line_actions", false

      sign_in @world.buyer.user
      get orders_request_url(order_request)
      assert_select "#buyer_line_actions"
    end
  end

  test "the orders routes are turned away while the feature is off" do
    with_settings(orders_settings(@world, feature_orders: "false")) do
      sign_in @world.buyer.user
      get to_buy_orders_purchases_url
      assert_redirected_to root_url
    end
  end

  test "an admin who switches an order to a card to reimburse records the buyer to pay back, not themselves" do
    with_orders(@world) do
      purchase = buy(@world, approved_request(@world).order_lines.to_a, paid_with: "Team card")
      sign_in @world.admin.user

      patch orders_purchase_url(purchase), params: { purchase: { paid_with: "Personal card — reimburse" } }

      assert_equal @world.buyer, purchase.reload.reimburse_to
    end
  end

  test "switching an order away from a card to reimburse clears who to pay back" do
    with_orders(@world) do
      purchase = buy(@world, approved_request(@world).order_lines.to_a, paid_with: "Personal card — reimburse",
        reimburse_to: @world.buyer)
      sign_in @world.buyer.user

      patch orders_purchase_url(purchase), params: { purchase: { paid_with: "Team card" } }

      assert_equal "Team card", purchase.reload.paid_with
      assert_nil purchase.reimburse_to
    end
  end

  test "editing an order keeps a Paid with choice that has since been renamed" do
    with_orders(@world) do
      purchase = buy(@world, approved_request(@world).order_lines.to_a, paid_with: "Team card")
      sign_in @world.buyer.user

      with_settings(orders_paid_with: JSON.generate([ { "label" => "Personal card — reimburse", "reimburse" => true },
                                                      { "label" => "Team debit card", "reimburse" => false } ])) do
        get edit_orders_purchase_url(purchase)
        assert_select "select[name='purchase[paid_with]'] option[selected]", text: "Team card"

        patch orders_purchase_url(purchase), params: { purchase: { paid_with: "Team card", tracking_url: "https://track.example/3" } }
      end

      purchase.reload
      assert_equal "Team card", purchase.paid_with
      assert_nil purchase.reimburse_to
      assert_equal "https://track.example/3", purchase.tracking_url
    end
  end
end
