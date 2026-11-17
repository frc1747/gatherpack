require "support/orders_world"

# The orders world (support/orders_world.rb) with inventory on top:
#
#   club's shop › cabinet (A) › bin (A-1), and the art room (art's own)
#   screws: a club item kept in the bin, order more at 10, bought from
#           Parts Depot (the world's preferred vendor)
#   motor:  a tracked club item kept in the bin
#
# The robotics manager manages robotics' inventory; the buyer holds a
# keeper badge, an inventory manager grant capped at the club.
module OrderInventoryWorld
  include OrdersWorld

  Stock = Struct.new(:shop, :cabinet, :bin, :art_room, :screws, :motor, :keeper_badge, keyword_init: true)

  def build_order_inventory_world
    # Some orders tests reset the extension registries; put the bridge back.
    OrderInventory.register!
    world = build_orders_world
    shop = Location.create!(team: world.club, name: "Shop")
    cabinet = Location.create!(parent: shop, name: "Cabinet", code: "A")
    bin = Location.create!(parent: cabinet, name: "Bin", code: "A-1")
    badge = Badge.create!(name: "Keeper #{SecureRandom.hex(3)}", short: "KP", color: "#000000",
      badge_type: world.buyer_badge.badge_type, permission: :added_by_admin)
    BadgeAssignment.create!(badge: badge, person: world.buyer)
    screws = Item.create!(team: world.club, name: "M4 screw", manufacturer: "Fastco", manufacturer_part_number: "M4-12",
      home_location: bin, reorder_point: 10)
    screws.item_sources.create!(vendor_name: "Parts Depot", vendor_part_number: "SCR-4", url: "https://partsdepot.example/p/SCR-4",
      preferred: true)
    motor = Item.create!(team: world.club, name: "Motor", tracked: true, home_location: bin)
    stock = Stock.new(shop: shop, cabinet: cabinet, bin: bin, art_room: Location.create!(team: world.art, name: "Art room"),
      screws: screws, motor: motor, keeper_badge: badge)
    [ world, stock ]
  end

  def with_both(world, stock, **overrides, &block)
    settings = orders_settings(world).merge(feature_inventory: "true",
      inventory_managers: "#{stock.keeper_badge.name} > #{world.club.name}").merge(overrides)
    with_settings(settings) do
      Orders::Current.reset
      Inventory::Current.reset
      block.call
    ensure
      Orders::Current.reset
      Inventory::Current.reset
    end
  end

  # A request for an item, approved and bought from Parts Depot.
  def ordered_line(world, line)
    order_request = approved_request(world, lines: [ line ])
    buy(world, order_request.order_lines.to_a, vendor: world.preferred_vendor)
    order_request.order_lines.first.reload
  end

  def put_away_params(location, **values)
    { order_inventory: { put_away: "1", location_id: location.id }.merge(values) }
  end
end
