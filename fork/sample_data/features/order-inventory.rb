# Sample data for feature/order-inventory.
# Loads after feature/orders and feature/inventory, and uses their people,
# vendors, places and items.
#
# - Where to buy entries are linked to the orders vendor of the same name
#   (the Store in Orders picker on the source form).
# - Shaft collars: Isla asked for 2 packs of 10 from the item, approved and
#   bought; 20 are on order, so the collar is off the reorder list while it's
#   still out of stock.
# - Anderson connectors: a box of 25 bought, delivered and put away in
#   drawer E-1, a Received change "from Parts Depot" with a link back.
# - 12V batteries: 2 bought and received as new units (tracked) in E-4,
#   waiting for labels.
# - Hex keys: a free-text line ("metric hex key set") bought and waiting to
#   be received, to try linking it to an item or Create item from this line.
# - Heat shrink: a draft from Order these, waiting for Isla to submit it.
Hbr::SampleData.feature "feature/order-inventory" do |s|
  facilities = s.team(:facilities)
  isla, mia = %w[Isla Mia].map { |first| s.person(first) }
  henry, gina = %w[Henry Gina].map { |first| s.person(first) }
  Orders::Current.reset
  Inventory::Current.reset

  # Sources saved before this layer (or before the migration) get the
  # matching vendor; new ones pick it up when saved.
  ItemSource.where(vendor_id: nil).find_each do |source|
    vendor = OrderInventory.match_vendor(source.vendor_name, source.url)
    source.update!(vendor: vendor) if vendor
  end
  linked = ItemSource.where.not(vendor_id: nil).count

  item = ->(name) { Item.find_by!(name: name) }
  collar = item.call("Shaft collar 1/2 in hex")
  anderson = item.call("Anderson connector 30 A")
  battery = item.call("12V battery")
  heat_shrink = item.call("Heat shrink assortment")
  parts = Vendor.find_by!(name: "Parts Depot")
  from_item = ->(stocked, quantity, **attrs) { OrderInventory.line_attributes(stocked).merge(quantity: quantity).merge(attrs) }

  # Builds a request once, by title; later runs leave it as it is.
  made = 0
  scenario = lambda do |title, person, lines, &block|
    next OrderRequest.find_by(title: title) if OrderRequest.exists?(title: title)

    made += 1
    order_request = OrderRequest.draft_for(person: person, team: facilities, lines: lines, title: title)
    block&.call(order_request)
    order_request.reload
  end
  approve_and_buy = lambda do |order_request|
    order_request.submit!(by: order_request.requested_by)
    order_request.reload.decide!(:approved, by: henry)
    lines = order_request.reload.order_lines.to_a
    Orders::RecordPurchase.new(buyer: gina, lines: lines, vendor: parts,
      prices: lines.to_h { |line| [ line.id, line.estimated_unit_price_cents ] },
      attributes: { ordered_on: s.clock.date(-3), payment_method: PaymentMethod.find_by!(name: "Team card"), expected_on: s.clock.date(3) }).call
    order_request.reload
  end
  put_away = lambda do |order_request, place|
    line = order_request.order_lines.first
    line.record_delivery!(by: isla, quantity: line.quantity, received_on: s.clock.date(-1),
      params: { order_inventory: { put_away: "1", location_id: place.id } })
  end

  scenario.call("Shaft collars", isla, [ from_item.call(collar, 2, unit: "pack", units_per: 10, estimated_unit_price_cents: 1_450) ],
    &approve_and_buy)

  scenario.call("Anderson connectors", isla,
    [ from_item.call(anderson, 1, unit: "box", units_per: 25, estimated_unit_price_cents: 2_200) ]) do |order_request|
    put_away.call(approve_and_buy.call(order_request), anderson.home_location)
  end

  scenario.call("Spare batteries", isla, [ from_item.call(battery, 2, estimated_unit_price_cents: 4_500) ]) do |order_request|
    put_away.call(approve_and_buy.call(order_request), battery.home_location)
  end

  scenario.call("Hex keys", mia, [ { description: "Metric hex key set", quantity: 1, estimated_unit_price_cents: 1_800 } ],
    &approve_and_buy)

  scenario.call("Restock: Heat shrink assortment", isla, [ from_item.call(heat_shrink, heat_shrink.suggested_quantity) ])

  s.report "#{linked} item sources linked to vendors; #{made} order-inventory requests made"
  s.expect("every Parts Depot source is linked to the vendor") do
    ItemSource.where(vendor_name: "Parts Depot").where.not(vendor_id: parts.id).none?
  end
  s.expect("the shaft collar is on order, off the reorder list and still out of stock") do
    collar.reload.on_order == 20 && !collar.on_reorder_list? && collar.out_of_stock?
  end
  s.expect("the Anderson connectors were put away in E-1 from Parts Depot") do
    anderson.stock_movements.received.where(reason: "Parts Depot", quantity: 25).where("note LIKE ?", "Order request:%").exists?
  end
  s.expect("two received batteries wait for labels") do
    battery.item_units.joins(:events).where(item_unit_events: { action: "received" }).where(code: [ nil, "" ]).distinct.count == 2
  end
  s.expect("the hex keys wait to be received, with no item") do
    OrderRequest.find_by(title: "Hex keys").order_lines.first.then { |line| line.item.nil? && line.open_to_receive? }
  end
  s.expect("Order these left a draft for heat shrink") do
    OrderRequest.find_by(title: "Restock: Heat shrink assortment").then { |draft| draft.draft? && draft.order_lines.first.item == heat_shrink }
  end
end
