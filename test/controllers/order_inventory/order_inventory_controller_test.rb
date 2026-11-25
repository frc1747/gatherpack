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
      assert_match "Adds 3 units of Motor; label them later.", response.body
    end
  end

  test "for a line without an item, the dialog asks which item it is and offers Create item to an inventory manager" do
    with_both(@world, @stock) do
      line = ordered_line(@world, { description: "small screws", quantity: 2 })
      sign_in @world.requester.user
      get new_orders_request_line_delivery_url(line.order_request, line)
      assert_select "input[type=checkbox][name='order_inventory[put_away]']:not([checked])"
      assert_select "label", text: "Which inventory item is it?"
      assert_select "input[name='order_inventory[create_item]']", count: 0

      sign_in @world.buyer.user
      get new_orders_request_line_delivery_url(line.order_request, line)
      assert_select "label", text: "Create an inventory item from this"
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

  test "a put-away that can't be done still records the delivery, and says why" do
    with_both(@world, @stock) do
      line = ordered_line(@world, { description: "M4 screw", quantity: 2, item: @stock.screws })
      sign_in @world.requester.user
      assert_no_difference -> { StockMovement.count } do
        post orders_request_line_deliveries_url(line.order_request, line), params: {
          order_delivery: { quantity: 2, received_on: Date.current.to_s, condition: "good", note: "Box was wet" },
          order_inventory: { put_away: "1", location_id: "" }
        }
      end
      assert_redirected_to orders_request_url(line.order_request)
      assert_equal "Recorded: M4 screw", flash[:notice]
      assert_equal "M4 screw was recorded but not put away: pick where to put it away", flash[:alert]
      assert_equal [ "Box was wet" ], line.reload.order_deliveries.map(&:note)

      follow_redirect!
      assert_match "was recorded but not put away", response.body
      get orders_request_url(line.order_request)
      assert_no_match "was recorded but not put away", response.body, "the problem shows once"
    end
  end

  test "Track this item isn't offered to a receiver who can't see the inventory item" do
    with_both(@world, @stock) do
      # A buyer for the club and the teams below, who isn't on robotics:
      # orders lets them receive robotics' request; inventory doesn't show
      # them robotics' item.
      purchaser = orders_person("Purchaser", teams: [ @world.club ], badges: [ @world.buyer_badge ])
      robotics_item = Item.create!(team: @world.robotics, name: "Robotics gear", home_location: @stock.bin)
      line = ordered_line(@world, { description: "Robotics gear", quantity: 2, item: robotics_item })
      assert_not Inventory::Access.for(purchaser).sees?(robotics_item)

      sign_in purchaser.user
      get new_orders_request_line_delivery_url(line.order_request, line)
      assert_response :success
      assert_select "[name='order_inventory[put_away]']", count: 0

      post orders_request_line_deliveries_url(line.order_request, line), params: {
        order_delivery: { quantity: 2, received_on: Date.current.to_s, condition: "good" },
        order_inventory: { put_away: "1", location_id: @stock.bin.id }
      }
      assert_equal 1, line.reload.order_deliveries.count
      assert_equal 0, robotics_item.total_stock
      assert_match "that inventory item isn't one you can see", flash[:alert]
    end
  end

  test "Track this item is offered unticked when the item's place isn't one the receiver can pick" do
    with_both(@world, @stock) do
      loose = Item.create!(team: @world.club, name: "Loose part")
      line = ordered_line(@world, { description: "Loose part", quantity: 1, item: loose })
      sign_in @world.requester.user
      get new_orders_request_line_delivery_url(line.order_request, line)
      assert_select "input[type=checkbox][name='order_inventory[put_away]']:not([checked])"
      assert_select "select[name='order_inventory[location_id]'] option[selected]", count: 0
    end
  end

  test "only someone inventory lets record received may change the number going into stock" do
    with_both(@world, @stock) do
      line = ordered_line(@world, { description: "M4 screw", quantity: 2, item: @stock.screws })
      sign_in @world.requester.user
      get new_orders_request_line_delivery_url(line.order_request, line)
      assert_select "input[name='order_inventory[quantity]'][readonly]"

      sign_in @world.buyer.user
      get new_orders_request_line_delivery_url(line.order_request, line)
      assert_select "input[name='order_inventory[quantity]']:not([readonly])"
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

  test "Order these has a breadcrumb back to Reorder and ends Cancel, Create draft request" do
    with_both(@world, @stock) do
      sign_in @world.buyer.user
      get new_order_inventory_reorder_draft_url(items: { @stock.screws.id => 20 })
      assert_response :success

      assert_select ".breadcrumb a[href=?]", inventory_reorder_path, "Reorder"
      assert_select ".breadcrumb", /Order these/
      labels = css_select(".orders-bar-fixed .btn").map { |node| node.text.presence || node["value"] }
      assert_equal [ "Cancel", "Create draft request" ], labels
      assert_select ".orders-bar-fixed a.btn-secondary[href=?]", inventory_reorder_path, "Cancel"
      assert_select ".orders-bar-fixed input.btn-primary[type=submit][value='Create draft request']"
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
