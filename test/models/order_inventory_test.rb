require "test_helper"
require "support/order_inventory_world"

class OrderInventoryTest < ActiveSupport::TestCase
  include OrderInventoryWorld

  setup { @world, @stock = build_order_inventory_world }

  def receive(line, quantity: line.quantity, by: @world.requester, condition: :good, params: {})
    line.record_delivery!(by: by, quantity: quantity, condition: condition, params: params)
  end

  # -- Line attributes -------------------------------------------------------

  test "an item's line takes its name, maker, part numbers, unit, link and the matching vendor, and links the item" do
    with_both(@world, @stock) do
      attributes = OrderInventory.line_attributes(@stock.screws)

      assert_equal "M4 screw", attributes[:description]
      assert_equal "Fastco", attributes[:manufacturer]
      assert_equal "M4-12", attributes[:manufacturer_part_number]
      assert_equal "each", attributes[:unit]
      assert_equal "SCR-4", attributes[:vendor_part_number]
      assert_equal "https://partsdepot.example/p/SCR-4", attributes[:url]
      assert_equal @world.preferred_vendor.id, attributes[:vendor_id]
      assert_nil attributes[:other_vendor_name]
      assert_equal @stock.screws, attributes[:item]
    end
  end

  test "a source's vendor is its own, else one with the same name, else one whose domain matches its link, else another store" do
    with_both(@world, @stock) do
      source = @stock.screws.preferred_source
      source.update_columns(vendor_id: @world.other_vendor.id)
      assert_equal @world.other_vendor, OrderInventory.vendor_for(source.reload)

      source.update_columns(vendor_id: nil, vendor_name: " parts depot ", url: nil)
      assert_equal @world.preferred_vendor, OrderInventory.vendor_for(source.reload)

      source.update_columns(vendor_name: "Barn online", url: "https://www.hardwarebarn.example/x")
      assert_equal @world.other_vendor, OrderInventory.vendor_for(source.reload)

      source.update_columns(vendor_name: "Corner shop", url: "https://corner.example/x")
      attributes = OrderInventory.line_attributes(@stock.screws.reload)
      assert_nil attributes[:vendor_id]
      assert_equal "Corner shop", attributes[:other_vendor_name]
    end
  end

  test "a new or renamed source picks up a matching vendor, and a picked one is kept" do
    with_both(@world, @stock) do
      source = @stock.screws.item_sources.create!(vendor_name: "Hardware Barn")
      assert_equal @world.other_vendor, source.vendor

      source.update!(vendor: @world.preferred_vendor, vendor_name: "Something else")
      assert_equal @world.preferred_vendor, source.reload.vendor
    end
  end

  test "the line entry extension links items and turns a picked item into line attributes" do
    entry = Orders.line_entry_extensions.all.find { |extension| extension.key == :order_inventory }
    assert_includes Orders.line_item_types, "Item"
    assert_equal "M4 screw", entry.callback.call(@stock.screws)[:description]
    assert_includes Inventory.extensions.source_permitted_params, :vendor_id
  end

  # -- On order --------------------------------------------------------------

  test "bought lines still to come count as on order in pieces, and keep the item off the reorder list" do
    with_both(@world, @stock) do
      StockMovement.record!(kind: :added, item: @stock.screws, location: @stock.bin, quantity: 4, person: @world.admin, reason: "Count")
      assert @stock.screws.on_reorder_list?

      draft_request(@world, lines: [ { description: "M4 screw", quantity: 5, item: @stock.screws } ])
      approved_request(@world, lines: [ { description: "M4 screw", quantity: 5, item: @stock.screws } ])
      assert_equal 0, @stock.screws.on_order, "requests not yet bought aren't on order"

      line = ordered_line(@world, { description: "M4 screw", quantity: 2, unit: "pack", units_per: 25, item: @stock.screws })
      assert_equal 50, @stock.screws.on_order
      assert_not @stock.screws.on_reorder_list?
      assert_not_includes Inventory::Reorder.new(@world.admin).rows.map(&:item), @stock.screws

      receive(line, quantity: 1)
      assert_equal 25, @stock.screws.on_order

      receive(line.reload, quantity: 1)
      assert_equal 0, @stock.screws.on_order
    end
  end

  test "nothing is on order while orders is off" do
    with_both(@world, @stock) do
      ordered_line(@world, { description: "M4 screw", quantity: 2, item: @stock.screws })
    end
    with_settings(feature_inventory: "true") do
      assert_equal 0, @stock.screws.on_order
    end
  end

  # -- Putting a delivery away -------------------------------------------------

  test "a delivery put away records received stock of quantity × units_per, from the purchase's vendor, with a link back" do
    with_both(@world, @stock) do
      line = ordered_line(@world, { description: "M4 screw", quantity: 2, unit: "box", units_per: 100, item: @stock.screws })
      receive(line, params: put_away_params(@stock.bin))

      movement = StockMovement.newest_first.first
      assert movement.received?
      assert_equal 200, movement.quantity
      assert_equal @stock.bin, movement.location
      assert_equal @world.requester, movement.person
      assert_equal "Parts Depot", movement.reason
      assert_includes movement.note, "/orders/requests/#{line.order_request.to_param}"
      assert_equal 200, @stock.screws.total_stock
    end
  end

  test "blank units_per means 1, and an inventory manager can change the number put away" do
    with_both(@world, @stock) do
      line = ordered_line(@world, { description: "M4 screw", quantity: 3, item: @stock.screws })
      receive(line, quantity: 2, params: put_away_params(@stock.bin))
      assert_equal 2, StockMovement.newest_first.first.quantity

      receive(line.reload, quantity: 1, by: @world.buyer, params: put_away_params(@stock.bin, quantity: "4"))
      assert_equal 4, StockMovement.newest_first.first.quantity
      assert_equal 6, @stock.screws.total_stock
    end
  end

  test "a member's own number isn't recorded: the delivery only vouches for what came" do
    with_both(@world, @stock) do
      line = ordered_line(@world, { description: "M4 screw", quantity: 1, unit: "box", units_per: 10, item: @stock.screws })
      assert_not Inventory::Access.for(@world.requester).may_record?("received", @stock.screws, @stock.bin)

      receive(line, params: put_away_params(@stock.bin, quantity: "5000"))
      assert_equal 10, StockMovement.newest_first.first.quantity
      assert_equal 10, @stock.screws.total_stock
    end
  end

  test "a member may give their own number where inventory lets members record received" do
    with_both(@world, @stock, inventory_member_kinds: "used, moved, counted, received") do
      line = ordered_line(@world, { description: "M4 screw", quantity: 1, item: @stock.screws })
      receive(line, params: put_away_params(@stock.bin, quantity: "3"))
      assert_equal 3, StockMovement.newest_first.first.quantity
    end
  end

  test "the dialog's words count units for a tracked item" do
    assert_equal "Adds 4 units of Motor; label them later.", OrderInventory.units_text(@stock.motor, 4)
    assert_equal "Adds 1 unit of Motor; label them later.", OrderInventory.units_text(@stock.motor, 1)
  end

  test "the dialog's words convert packs to pieces" do
    line = OrderLine.new(unit: "pack", units_per: 100, quantity: 2)
    assert_equal "2 packs = 200 each", OrderInventory.conversion_text(line, 2, item: @stock.screws)
    assert_equal "1 pack = 100 each", OrderInventory.conversion_text(line, 1, item: @stock.screws)
    assert_equal "3 each", OrderInventory.conversion_text(OrderLine.new(quantity: 3), 3, item: @stock.screws)
  end

  test "a tracked item becomes one unit per piece instead of stock" do
    with_both(@world, @stock) do
      line = ordered_line(@world, { description: "Motor", quantity: 2, unit: "pair", units_per: 2, item: @stock.motor })

      assert_no_difference -> { StockMovement.count } do
        assert_difference -> { @stock.motor.item_units.count }, 4 do
          receive(line, params: put_away_params(@stock.bin))
        end
      end
      units = @stock.motor.item_units
      assert units.all? { |unit| unit.location == @stock.bin && unit.code.blank? }
      assert_equal %w[received], units.flat_map { |unit| unit.events.map(&:action) }.uniq
      assert_equal 4, @stock.motor.total_stock
    end
  end

  test "without Track this item, or for a damaged delivery, receiving stays an acknowledgement" do
    with_both(@world, @stock) do
      line = ordered_line(@world, { description: "M4 screw", quantity: 3, item: @stock.screws })

      assert_no_difference -> { StockMovement.count } do
        receive(line, quantity: 1, params: put_away_params(@stock.bin, put_away: "0"))
        receive(line.reload, quantity: 1)
        receive(line.reload, quantity: 1, condition: :damaged, params: put_away_params(@stock.bin))
      end
      assert_equal 2, line.reload.order_deliveries.count(&:good?)
    end
  end

  test "nothing goes into stock while inventory is off" do
    line = with_both(@world, @stock) { ordered_line(@world, { description: "M4 screw", quantity: 1, item: @stock.screws }) }
    with_orders(@world) do
      assert_no_difference -> { StockMovement.count } do
        receive(line, params: put_away_params(@stock.bin))
      end
      assert line.reload.received?
    end
  end

  test "a line without an item is linked to the item picked, on the timeline" do
    with_both(@world, @stock) do
      line = ordered_line(@world, { description: "small screws", quantity: 5 })
      receive(line, params: put_away_params(@stock.bin, item_id: @stock.screws.id))

      assert_equal @stock.screws, line.reload.item
      assert_equal 5, @stock.screws.total_stock
      event = line.order_request.events.where(action: "edited", order_line: line).last
      assert_equal [ nil, "M4 screw" ], event.field_changes["item"]
    end
  end

  test "an order item with no inventory item and nothing picked isn't put away, but the delivery is recorded" do
    with_both(@world, @stock) do
      line = ordered_line(@world, { description: "small screws", quantity: 5 })
      assert_no_difference -> { StockMovement.count } do
        receive(line, params: put_away_params(@stock.bin))
      end
      assert_equal 1, line.reload.order_deliveries.count
      assert line.received?
      assert_equal [ "small screws was recorded but not put away: pick the inventory item it is, or create one from it" ],
        OrderInventory::Current.problems
    end
  end

  test "a put-away that fails part way leaves nothing of it behind" do
    with_both(@world, @stock) do
      line = ordered_line(@world, { description: "small screws", quantity: 5 })
      receive(line, params: put_away_params(@stock.art_room, item_id: @stock.screws.id))

      assert_nil line.reload.item, "the link to the inventory item is undone with the rest"
      assert_not line.order_request.events.where(action: "edited", order_line: line).exists?
      assert line.received?
    end
  end

  test "Create item from this line makes the item with its store as the preferred source, for an inventory manager" do
    with_both(@world, @stock) do
      line = ordered_line(@world, { description: "Hex key set", manufacturer: "Toolco", manufacturer_part_number: "HK-9",
        vendor_part_number: "HK9-PD", url: "https://partsdepot.example/p/HK9-PD", quantity: 1 })
      receive(line, by: @world.buyer, params: put_away_params(@stock.bin, create_item: "1"))

      item = line.reload.item
      assert_equal "Hex key set", item.name
      assert_equal [ "Toolco", "HK-9", @world.robotics, @stock.bin ], [ item.manufacturer, item.manufacturer_part_number, item.team, item.home_location ]
      source = item.preferred_source
      assert_equal [ "Parts Depot", @world.preferred_vendor, "HK9-PD" ], [ source.vendor_name, source.vendor, source.vendor_part_number ]
      assert_equal 1, item.total_stock
    end
  end

  test "Create item from this line counts a line bought in packs in pieces" do
    with_both(@world, @stock) do
      line = ordered_line(@world, { description: "Zip ties", unit: "bag", units_per: 50, quantity: 2 })
      receive(line, by: @world.buyer, params: put_away_params(@stock.bin, create_item: "1"))

      item = line.reload.item
      assert_equal "each", item.unit
      assert_equal 100, item.total_stock
    end
  end

  test "only an inventory manager may create an inventory item from an order item" do
    with_both(@world, @stock) do
      line = ordered_line(@world, { description: "Hex key set", quantity: 1 })
      assert_no_difference -> { Item.count } do
        receive(line, params: put_away_params(@stock.bin, create_item: "1"))
      end
      assert_match "only an inventory manager can create", OrderInventory::Current.problems.join
      assert_equal 1, line.reload.order_deliveries.count
    end
  end

  test "a place or inventory item the receiver can't see isn't put away" do
    with_both(@world, @stock) do
      line = ordered_line(@world, { description: "M4 screw", quantity: 1, item: @stock.screws })
      art_item = Item.create!(team: @world.art, name: "Paint")
      other = ordered_line(@world, { description: "Paint?", quantity: 1 })

      assert_no_difference -> { StockMovement.count } do
        receive(line, params: put_away_params(@stock.art_room))
        receive(other, params: put_away_params(@stock.bin, item_id: art_item.id))
      end
      assert_match "Art room isn't a place you can see", OrderInventory::Current.problems.first
      assert_match "that inventory item isn't one you can see", OrderInventory::Current.problems.second
      assert_nil other.reload.item
      assert [ line.reload, other ].all?(&:received?)
    end
  end

  test "a member who isn't an inventory manager can still put a delivery away" do
    with_both(@world, @stock) do
      line = ordered_line(@world, { description: "M4 screw", quantity: 1, item: @stock.screws })
      assert_not Inventory::Access.for(@world.requester).may_record?("received", @stock.screws, @stock.bin)
      receive(line, params: put_away_params(@stock.bin))
      assert_equal 1, @stock.screws.total_stock
    end
  end

  # -- Recent orders and the note ----------------------------------------------

  test "Recent orders lists the newest order items for the inventory item, on requests the viewer sees" do
    with_both(@world, @stock) do
      mine = ordered_line(@world, { description: "M4 screw", quantity: 2, item: @stock.screws })
      draft_request(@world, by: @world.teammate, lines: [ { description: "M4 screw", item: @stock.screws } ])
      ordered_line(@world, { description: "Gear", quantity: 1 })

      assert_equal [ mine ], OrderInventory.recent_lines(@stock.screws, @world.requester).to_a
      assert_empty OrderInventory.recent_lines(@stock.screws, @world.outsider).to_a

      panel = Inventory.extensions.item_panels(@stock.screws, @world.requester).find { |entry| entry.key == :recent_orders }
      html = ApplicationController.render(partial: panel.partial, locals: { item: @stock.screws, viewer: @world.requester })
      assert_includes html, "Recent orders"
      assert_includes html, "/orders/requests/#{mine.order_request.to_param}"
      assert_includes html, "Ordered"
    end
    with_settings(feature_inventory: "true") do
      assert_empty Inventory.extensions.item_panels(@stock.screws, @world.requester).select { |entry| entry.key == :recent_orders }
    end
  end

  test "the movement's note names the request with its path, which the note helper links" do
    with_both(@world, @stock) do
      line = ordered_line(@world, { description: "M4 screw", quantity: 1, item: @stock.screws })
      receive(line, params: put_away_params(@stock.bin))
      note = StockMovement.newest_first.first.note
      path = "/orders/requests/#{line.order_request.to_param}"
      assert_equal "Order request: #{line.order_request.display_title} (#{path})", note

      html = ApplicationController.helpers.order_inventory_note(note)
      assert_includes html, %(<a href="#{path}">open the order request</a>)
      assert_equal "Plain &lt;b&gt;note&lt;/b&gt;", ApplicationController.helpers.order_inventory_note("Plain <b>note</b>")
    end
  end
end
