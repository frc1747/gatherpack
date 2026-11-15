require "test_helper"
require "support/order_inventory_world"

class OrderInventory::OrderInventoryControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include OrderInventoryWorld

  setup do
    # The reorder action returns a path; the app allows only its own host.
    host! "localhost"
    @world, @stock = build_order_inventory_world
  end

  # -- Pick from what we stock -------------------------------------------------

  test "the request form offers Pick from what we stock only while both features are on" do
    with_both(@world, @stock) do
      sign_in @world.requester.user
      get new_orders_request_url
      assert_select "label", text: "Pick from what we stock"
    end
    with_orders(@world) do
      get new_orders_request_url
      assert_select "label", text: "Pick from what we stock", count: 0
    end
  end

  test "the item search returns items the viewer sees, with the line to fill in" do
    with_both(@world, @stock) do
      Item.create!(team: @world.art, name: "M4 art screw")
      sign_in @world.requester.user
      get order_inventory_items_url(format: :json, q: "SCR-4")
      assert_response :success

      results = response.parsed_body
      assert_equal [ "M4 screw" ], results.map { |item| item["name"] }
      line = results.first["line"]
      assert_equal [ "M4 screw", "Fastco", "M4-12", "SCR-4", "https://partsdepot.example/p/SCR-4" ],
        line.values_at("description", "manufacturer", "manufacturer_part_number", "vendor_part_number", "url")
      assert_equal [ @world.preferred_vendor.id, "Item", @stock.screws.id ], line.values_at("vendor_choice", "item_type", "item_id")

      get order_inventory_items_url(format: :json, q: "M4")
      assert_equal [ "M4 screw" ], response.parsed_body.map { |item| item["name"] }
    end
  end

  test "the order-inventory pages are turned away unless both features are on" do
    with_orders(@world) do
      sign_in @world.requester.user
      get order_inventory_items_url(format: :json, q: "M4")
      assert_redirected_to root_url
    end
  end

  test "a picked item saves linked to the line" do
    with_both(@world, @stock) do
      sign_in @world.requester.user
      post orders_requests_url, params: { order_request: { lines: { "0" => {
        description: "M4 screw", quantity: "3", vendor_choice: @world.preferred_vendor.id, item_type: "Item", item_id: @stock.screws.id
      } } } }
      line = OrderRequest.order(:created_at).last.order_lines.first
      assert_equal @stock.screws, line.item
    end
  end

  # -- Receive dialog ----------------------------------------------------------

  test "the receive dialog offers Put away in and Track this item, ticked for a line with an item" do
    with_both(@world, @stock) do
      line = ordered_line(@world, { description: "M4 screw", quantity: 2, unit: "pack", units_per: 100, item: @stock.screws })
      sign_in @world.requester.user
      get new_orders_request_line_delivery_url(line.order_request, line)
      assert_response :success
      assert_select "input[type=checkbox][name='order_inventory[put_away]'][checked]"
      assert_select "select[name='order_inventory[location_id]'] option[selected]", text: "Shop › Cabinet › Bin"
      assert_select "select[name='order_inventory[location_id]'] option", text: /Art room/, count: 0
      assert_select "input[name='order_inventory[quantity]'][value='200']"
      assert_match "2 packs = 200 each", response.body
      assert_select "input[name='order_inventory[create_item]']", count: 0
    end
  end

  test "the receive dialog for a tracked item says it adds units" do
    with_both(@world, @stock) do
      line = ordered_line(@world, { description: "Motor", quantity: 3, item: @stock.motor })
      sign_in @world.requester.user
      get new_orders_request_line_delivery_url(line.order_request, line)
      assert_match "Adds 3 Motor as units; label them later.", response.body
    end
  end

  test "for a line without an item, the dialog asks which item it is and offers Create item to an inventory manager" do
    with_both(@world, @stock) do
      line = ordered_line(@world, { description: "small screws", quantity: 2 })
      sign_in @world.requester.user
      get new_orders_request_line_delivery_url(line.order_request, line)
      assert_select "input[type=checkbox][name='order_inventory[put_away]']:not([checked])"
      assert_select "label", text: "Which item is it?"
      assert_select "input[name='order_inventory[create_item]']", count: 0

      sign_in @world.buyer.user
      get new_orders_request_line_delivery_url(line.order_request, line)
      assert_select "label", text: "Create item from this line"
    end
  end

  test "recording a delivery from the dialog puts it away" do
    with_both(@world, @stock) do
      line = ordered_line(@world, { description: "M4 screw", quantity: 2, unit: "pack", units_per: 100, item: @stock.screws })
      sign_in @world.requester.user
      post orders_request_line_deliveries_url(line.order_request, line), params: {
        order_delivery: { quantity: 2, received_on: Date.current.to_s, condition: "good" },
        order_inventory: { put_away: "1", location_id: @stock.bin.id, quantity: "200" }
      }
      assert_redirected_to orders_request_url(line.order_request)
      assert_equal 200, @stock.screws.total_stock
    end
  end

  test "a refused put-away shows as a message and records nothing" do
    with_both(@world, @stock) do
      line = ordered_line(@world, { description: "M4 screw", quantity: 2, item: @stock.screws })
      sign_in @world.requester.user
      post orders_request_line_deliveries_url(line.order_request, line), params: {
        order_delivery: { quantity: 2, received_on: Date.current.to_s, condition: "good" },
        order_inventory: { put_away: "1", location_id: "" }
      }
      assert_response :redirect
      assert_equal "Pick where to put it away", flash[:alert]
      assert_equal 0, line.reload.order_deliveries.count
    end
  end

  test "the dialog has no inventory fields while inventory is off" do
    line = with_both(@world, @stock) { ordered_line(@world, { description: "M4 screw", quantity: 1, item: @stock.screws }) }
    with_orders(@world) do
      sign_in @world.requester.user
      get new_orders_request_line_delivery_url(line.order_request, line)
      assert_response :success
      assert_select "[name='order_inventory[put_away]']", count: 0
    end
  end

  # -- Order these -------------------------------------------------------------

  test "Order these is a reorder action for requesters, pointing at a draft for the ticked items" do
    with_both(@world, @stock) do
      action = Inventory.extensions.reorder_actions(@world.buyer).find { |entry| entry.key == :order_these }
      assert_equal "Order these", action.label
      path = action.path.call([ [ @stock.screws, 20 ] ])
      assert_equal new_order_inventory_reorder_draft_path(items: { @stock.screws.id => 20 }), path
    end
    with_orders(@world) do
      assert_not Inventory.extensions.reorder_actions(@world.buyer).map(&:key).include?(:order_these)
    end
  end

  test "Order these starts a draft with a line from each item on the reorder list" do
    with_both(@world, @stock) do
      StockMovement.record!(kind: :added, item: @stock.screws, location: @stock.bin, quantity: 3, person: @world.admin, reason: "Count")
      no_source = Item.create!(team: @world.club, name: "Washer", reorder_point: 5)
      rows = Inventory::Reorder.new(@world.buyer).rows
      assert_equal [ "M4 screw", "Washer" ], rows.map { |row| row.item.name }.sort
      action = Inventory.extensions.reorder_actions(@world.buyer).find { |entry| entry.key == :order_these }

      sign_in @world.buyer.user
      get action.path.call(rows.map { |row| [ row.item, row.suggested_quantity ] })
      assert_response :success
      assert_select "h1", text: "Order these"
      assert_select "input[name='items[#{@stock.screws.id}]'][value='17']"

      post order_inventory_reorder_drafts_url, params: { team_id: @world.robotics.id,
        items: { @stock.screws.id => "20", no_source.id => "5" } }
      draft = OrderRequest.order(:created_at).last
      assert_redirected_to edit_orders_request_url(draft)
      assert draft.draft?
      assert_equal [ @world.buyer, @world.robotics ], [ draft.requested_by, draft.team ]

      screws, washers = draft.order_lines.order(:position).to_a
      assert_equal [ "M4 screw", 20, @world.preferred_vendor, "SCR-4", @stock.screws ],
        [ screws.description, screws.quantity, screws.vendor, screws.vendor_part_number, screws.item ]
      assert_equal [ "Washer", 5, nil, no_source ], [ washers.description, washers.quantity, washers.vendor, washers.item ]
    end
  end

  test "Order these leaves out items the viewer doesn't see and refuses a team they can't ask for" do
    with_both(@world, @stock) do
      art_item = Item.create!(team: @world.art, name: "Paint", reorder_point: 1)
      sign_in @world.requester.user
      post order_inventory_reorder_drafts_url, params: { team_id: @world.robotics.id,
        items: { @stock.screws.id => "2", art_item.id => "4" } }
      draft = OrderRequest.order(:created_at).last
      assert_equal [ "M4 screw" ], draft.order_lines.map(&:description)

      assert_no_difference -> { OrderRequest.count } do
        post order_inventory_reorder_drafts_url, params: { team_id: @world.art.id, items: { @stock.screws.id => "2" } }
      end
      assert_equal "Pick a team you can ask for", flash[:alert]
    end
  end
end
