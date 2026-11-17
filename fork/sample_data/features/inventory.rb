# Sample data for feature/inventory.
#
# Northwind keeps parts in a Build shop (the community's top-level team):
# Cabinet A (bins A-1 to A-6), an Electrical cart (drawers E-1 to E-4), a
# Wire shelf and a Robot cart carrying the Competition and Practice robots;
# a Demo board stands on its own. Youth Program has its own Outreach closet,
# and keeps one item (Craft wire) on the Build shop's Wire shelf.
#
# Lists (Setup > Orders and Inventory): the Machine place type is renamed
# Robot (the robots are its places) and a second type, Display, holds the
# Demo board, so the menu shows Robots and Displays. Stock units are the
# defaults plus "spool", retired but still on Craft wire. Part conditions
# and reading types are the defaults plus Internal resistance (mΩ) and
# Charge cycles.
#
# Isla holds the Inventory Manager badge, capped at Operations, so she
# manages Operations' and its crews' inventory (Safety glasses and the
# Anderson connectors are Operations') but not the community's.
# Adam (admin) manages everything. Members record Used, Moved and Counted.
#
# Stock states: Zip ties and Heat shrink are running low, the 1/2 in shaft
# collar is out of stock, M5 nylock nuts are below zero in A-4 ("Needs a
# count"), wire ferrules have no source, old battery leads are inactive.
# History covers every kind: a starting import, used by Ella, Mia, Noah and
# Grace, a move between cabinets, a count that matched and one that found
# fewer, a removed item, a received box, a donated box, and an undone used.
#
# Tracked: NEO brushless motors (12: 6 in three swerve modules on the
# Competition robot, 2 in a fourth module on the Practice robot, 2 in a bin,
# 1 Needs repair, 1 Retired), Swerve modules (4, 2 motors each) and 12V
# batteries (10, with resistance and charge-cycle readings; one Worn).
Hbr::SampleData.feature "feature/inventory" do |s|
  s.enable_feature :inventory
  root = s.team(:root)
  operations = s.team(:operations)
  facilities = s.team(:facilities)
  logistics = s.team(:logistics)
  youth = s.team(:youth)
  admin = s.login(:admin)

  ella, isla, mia, noah, grace = %w[Ella Isla Mia Noah Grace].map { |first| s.person(first) }
  [ ella, isla, mia ].each { |person| s.member!(person, facilities) }
  s.member!(noah, logistics)
  s.member!(grace, youth)

  award = BadgeType.find_or_create_by!(name: "Award")
  keeper = s.upsert!(Badge, { name: "Inventory Manager" }, badge_type: award, team: nil, permission: "added_by_admin",
    color: "#613583", short: "boxes-stacked")
  BadgeAssignment.find_or_create_by!(badge: keeper, person: isla)
  s.setting :inventory_managers, "Inventory Manager > #{operations.name}"
  s.setting :inventory_member_kinds, "used, moved, counted"
  s.setting :inventory_reorder_notice, "daily"
  Inventory::Current.reset

  # Lists: the defaults, a renamed Machine type, a second type parts get
  # installed on, and a retired stock unit kept on an old item.
  Inventory::Lists.seed_defaults!
  LocationType.find_by!(key: "machine").update!(name: "Robot", plural: "Robots")
  display = s.upsert!(LocationType, { name: "Display" }, plural: "Displays", holds_stock: false, holds_installed_parts: true)
  storage = LocationType.find_by!(key: "storage")
  robot_type = LocationType.find_by!(key: "machine")
  spool = s.upsert!(StockUnit, { name: "spool" }, plural: "spools")
  # The catalog's units, by name or plural ("ft" is the foot row).
  units = ->(text) { StockUnit.named({ "ft" => "foot" }.fetch(text, text)) || raise("No stock unit #{text}") }
  resistance = s.upsert!(ReadingType, { name: "Internal resistance" }, unit_label: "mΩ")
  charge_cycles = s.upsert!(ReadingType, { name: "Charge cycles" }, unit_label: nil)

  # Places.
  place = lambda do |name, team: nil, parent: nil, code: nil, type: storage, position: 0|
    s.upsert!(Location, { name: name, parent_id: parent&.id }, team: team || parent.team, code: code, location_type: type,
      position: position, active: true)
  end
  shop = place.call("Build shop", team: root)
  cabinet = place.call("Cabinet A", parent: shop, code: "A", position: 1)
  bins = (1..6).to_h { |n| [ "A-#{n}", place.call("Bin #{n}", parent: cabinet, code: "A-#{n}", position: n) ] }
  cart = place.call("Electrical cart", parent: shop, code: "E", position: 2)
  drawers = (1..4).to_h { |n| [ "E-#{n}", place.call("Drawer #{n}", parent: cart, code: "E-#{n}", position: n) ] }
  wire_shelf = place.call("Wire shelf", parent: shop, code: "W", position: 3)
  robot_cart = place.call("Robot cart", parent: shop, code: "R", position: 4)
  competition = place.call("Competition robot", parent: robot_cart, code: "R-1", type: robot_type, position: 1)
  practice = place.call("Practice robot", parent: robot_cart, code: "R-2", type: robot_type, position: 2)
  demo = place.call("Demo board", team: root, code: "D", type: display)
  closet = place.call("Outreach closet", team: youth, code: "O")
  places = bins.merge(drawers).merge("W" => wire_shelf, "O" => closet)

  # Items: name, category, manufacturer, part number, unit, home, order more
  # at, order how many, vendor, vendor part number, starting count.
  catalog = [
    [ "M4 x 12 socket head screw", "Fasteners", "Fastenal Generic", "SHCS-M4-12", "each", "A-1", 50, 200, "Parts Depot", "PD-4412", 180 ],
    [ "M5 nylock nut", "Fasteners", "Fastenal Generic", "NUT-M5-NL", "each", "A-4", 40, 100, "Parts Depot", "PD-5501", 10 ],
    [ "10-32 button head screw", "Fasteners", "Bolt Co", "BHCS-1032-050", "each", "A-2", 50, 100, "Hardware Barn", "HB-1032", 120 ],
    [ "Rivet 3/16 in", "Fasteners", "Bolt Co", "RIV-316", "each", "A-3", 30, 100, "Hardware Barn", "HB-R316", 75 ],
    [ "Zip ties 8 in", "Consumables", "TieRight", "ZT-8-100", "each", "A-5", 50, 200, "Hardware Barn", "HB-ZT8", 60 ],
    [ "Heat shrink assortment", "Electrical", "WireWorks", "HS-ASST", "pack", "E-2", 3, 4, "Parts Depot", "PD-HS1", 5 ],
    [ "Wire ferrules 18 AWG", "Electrical", "WireWorks", "FER-18", "each", "E-3", 50, nil, nil, nil, 140 ],
    [ "Anderson connector 30 A", "Electrical", "PowerPole", "PP30", "each", "E-1", 10, 25, "Parts Depot", "PD-PP30", 32 ],
    [ "18 AWG wire, red", "Electrical", "WireWorks", "W18-RED", "ft", "W", 25, 100, "Parts Depot", "PD-W18R", 150 ],
    [ "18 AWG wire, black", "Electrical", "WireWorks", "W18-BLK", "ft", "W", 25, 100, "Parts Depot", "PD-W18B", 140 ],
    [ "12 AWG wire, red", "Electrical", "WireWorks", "W12-RED", "ft", "W", 20, 50, "Parts Depot", "PD-W12R", 60 ],
    [ "Flanged bearing 1/2 in hex", "Bearings", "SpinRight", "FB-12HEX", "each", "A-6", 8, 16, "Parts Depot", "PD-FB12", 24 ],
    [ "Thrust bearing 3/8 in", "Bearings", "SpinRight", "TB-38", "each", "A-6", 4, 10, "Parts Depot", "PD-TB38", 12 ],
    [ "Shaft collar 1/2 in hex", "Bearings", "SpinRight", "SC-12HEX", "each", "A-3", 6, 12, "Parts Depot", "PD-SC12", 4 ],
    [ "Pneumatic tubing 1/4 in", "Pneumatics", "AirLine", "PT-14", "ft", "W", 10, 25, "Hardware Barn", "HB-PT14", 40 ],
    [ "Push-to-connect fitting 1/4 in", "Pneumatics", "AirLine", "PTC-14", "each", "E-4", 6, 12, "Hardware Barn", "HB-PTC14", 18 ],
    [ "Solenoid valve", "Pneumatics", "AirLine", "SOL-12V", "each", "E-4", 2, 2, "Parts Depot", "PD-SOL", 4 ],
    [ "Hex key set", "Tools", "ToolPro", "HEX-SET-M", "each", "A-2", 1, 2, "Hardware Barn", "HB-HEXM", 3 ],
    [ "Wire strippers", "Tools", "ToolPro", "WS-1022", "each", "E-1", 1, 2, "Hardware Barn", "HB-WS22", 2 ],
    [ "Crimper, ferrule", "Tools", "ToolPro", "CR-FER", "each", "E-1", 1, 1, "Hardware Barn", "HB-CRF", 1 ],
    [ "Safety glasses", "Tools", "SafeSight", "SG-CLR", "each", "A-5", 10, 10, "Hardware Barn", "HB-SG", 18 ],
    [ "Electrical tape", "Consumables", "TapeCo", "ET-BLK", "each", "E-2", 3, 6, "Office Supply Co", "OS-ET", 7 ],
    [ "Threadlocker, blue", "Consumables", "LockTite Generic", "TL-BLU", "each", "A-1", 1, 2, "Hardware Barn", "HB-TLB", 2 ],
    [ "Old battery leads", "Electrical", "WireWorks", "BL-OLD", "each", "E-3", nil, nil, "Parts Depot", "PD-BLO", 6 ]
  ]
  # Operations owns its safety and power supplies, which Isla manages.
  owners = { "Safety glasses" => operations, "Anderson connector 30 A" => operations }
  items = catalog.to_h do |name, category, maker, part, unit, home, point, quantity, vendor, vendor_part, _start|
    item = s.upsert!(Item, { name: name }, team: owners.fetch(name, root), category: category, manufacturer: maker, manufacturer_part_number: part,
      stock_unit: units.call(unit), home_location: places.fetch(home), reorder_point: point, reorder_quantity: quantity, active: true, tracked: false)
    if vendor
      s.upsert!(ItemSource, { item_id: item.id, vendor_name: vendor }, vendor_part_number: vendor_part,
        url: "https://#{vendor.downcase.delete(" ")}.example/p/#{vendor_part}", preferred: true, position: 0)
    end
    [ name, item ]
  end
  craft_wire = s.upsert!(Item, { name: "Craft wire" }, team: youth, category: "Consumables", manufacturer: "WireWorks",
    manufacturer_part_number: "CW-20", stock_unit: spool, home_location: wire_shelf, reorder_point: 20, reorder_quantity: 50, active: true)
  s.upsert!(ItemSource, { item_id: craft_wire.id, vendor_name: "Office Supply Co" }, vendor_part_number: "OS-CW20", preferred: true)
  spool.update!(active: false)
  felt = s.upsert!(Item, { name: "Felt sheets" }, team: youth, category: "Consumables", manufacturer: "CraftCo",
    manufacturer_part_number: "FS-9", stock_unit: units.call("pack"), home_location: closet, reorder_point: 2, active: true)

  # History, written once: later runs leave it as it is.
  recorded = 0
  history = lambda do |item, &block|
    next if StockMovement.where(item_id: item.id).exists?

    block.call
    recorded += 1
  end
  record = lambda do |kind, item, quantity, person: admin, location: item.home_location, **options|
    StockMovement.record!(kind: kind, item: item, location: location, quantity: quantity, person: person, **options)
  end

  catalog.each do |name, *, start|
    history.call(items[name]) { record.call(:added, items[name], start, reason: "Imported") }
  end
  history.call(craft_wire) { record.call(:added, craft_wire, 80, reason: "Imported") }
  history.call(felt) { record.call(:added, felt, 4, reason: "Imported") }

  screws = items["M4 x 12 socket head screw"]
  if StockMovement.where(item_id: screws.id).count == 1
    record.call(:used, screws, 12, person: ella, reason: "Intake frame")
    record.call(:used, screws, 8, person: mia)
    record.call(:moved, screws, 40, person: noah, to_location: drawers["E-1"])
    record.call(:counted, screws, 120, person: ella)                          # matched
    record.call(:used, items["10-32 button head screw"], 6, person: grace, reason: "Demo stand")
    record.call(:counted, items["Rivet 3/16 in"], 61, person: mia)            # found fewer
    record.call(:used, items["Zip ties 8 in"], 20, person: noah)              # running low
    record.call(:used, items["Heat shrink assortment"], 2, person: ella)      # running low
    record.call(:used, items["Shaft collar 1/2 in hex"], 4, person: mia)      # out of stock
    record.call(:used, items["M5 nylock nut"], 12, person: noah)              # below zero in A-4
    record.call(:added, items["M5 nylock nut"], 20, location: bins["A-5"], reason: "Found a bag")
    record.call(:removed, items["Safety glasses"], 2, person: isla, reason: "Scratched")
    record.call(:received, items["Anderson connector 30 A"], 20, person: isla, reason: "Parts Depot")
    record.call(:added, items["Pneumatic tubing 1/4 in"], 25, reason: "Donated by a sponsor")
    oops = record.call(:used, items["Electrical tape"], 5, person: grace)
    oops.undo!(by: grace)
    record.call(:used, craft_wire, 15, person: grace, reason: "Outreach booth")
  end
  items["Old battery leads"].update!(active: false)

  # Tracked parts.
  tracked = lambda do |name, category, maker, part, home, point, readings = []|
    item = s.upsert!(Item, { name: name }, team: root, category: category, manufacturer: maker, manufacturer_part_number: part,
      stock_unit: units.call("each"), home_location: home, reorder_point: point, reading_type_ids: readings.map(&:id), active: true)
    item.start_tracking!(by: admin) unless item.tracked?
    item
  end
  neo = tracked.call("NEO brushless motor", "Motors", "SparkWorks", "NEO-1650", drawers["E-1"], 3)
  swerve = tracked.call("Swerve module", "Drivetrain", "SwerveCo", "SM-MK4", bins["A-6"], 1)
  battery = tracked.call("12V battery", "Electrical", "PowerCell", "BAT-18AH", drawers["E-4"], 4,
    [ resistance, charge_cycles ])

  unit = lambda do |item, code, location|
    ItemUnit.find_by(code: code, item_id: item.id) ||
      ItemUnit.receive!(item: item, location: location, count: 1, person: admin, note: "Labelled").first.tap { |made| made.update!(code: code) }
  end
  motors = (1..12).map { |n| unit.call(neo, format("NEO-%02d", n), drawers["E-1"]) }
  modules = (1..4).map { |n| unit.call(swerve, "SW-#{n}", bins["A-6"]) }
  batteries = (1..10).map { |n| unit.call(battery, format("BAT-2026-%02d", n), drawers["E-4"]) }

  if ItemUnitEvent.where(item_unit_id: motors.map(&:id), action: "install").none?
    modules.each_with_index do |swerve_unit, index|
      motors[index * 2].install!(into: swerve_unit, by: noah)
      motors[(index * 2) + 1].install!(into: swerve_unit, by: noah)
      swerve_unit.reload.install!(into: index < 3 ? competition : practice, by: noah)
    end
    motors[10].mark_for_repair!(by: ella, note: "Grinds when spun by hand")
    motors[11].retire!(by: admin, note: "Burnt windings")
    batteries[0].install!(into: competition, by: noah)
    batteries[1].install!(into: practice, by: noah)
    batteries.each_with_index do |battery_unit, index|
      battery_unit.reload.check!(by: mia, condition: "good",
        readings: { "Internal resistance" => 11 + index, "Charge cycles" => 40 + (index * 15) })
    end
    batteries[9].reload.check!(by: isla, condition: "worn", readings: { "Internal resistance" => 26, "Charge cycles" => 310 },
      note: "Resistance climbing; practice use only")
    batteries[2].reload.install!(into: demo, by: grace)
  end

  s.report "#{Location.count} places (#{Location.machine.count} that parts get installed on), " \
    "#{Item.where(tracked: false).count} counted items, " \
    "#{ItemUnit.count} units; #{recorded} item histories written"
  s.expect("Zip ties and Heat shrink are running low") do
    [ items["Zip ties 8 in"], items["Heat shrink assortment"] ].all? { |item| item.reload.on_reorder_list? }
  end
  s.expect("the shaft collar is out of stock") { items["Shaft collar 1/2 in hex"].out_of_stock? }
  s.expect("Bin A-4 needs a count") { bins["A-4"].needs_count? }
  s.expect("ferrules have no source") { items["Wire ferrules 18 AWG"].item_sources.none? }
  s.expect("the Competition robot carries three modules with six motors") do
    competition.item_units.where(item: swerve).count == 3 && competition.item_units.where(item: neo).count == 6
  end
  s.expect("two spare NEOs, below the reorder point of 3") { neo.total_stock == 2 && neo.on_reorder_list? }
  s.expect("one battery is Worn") { battery.item_units.where(unit_condition: UnitCondition.find_by!(key: "worn")).count == 1 }
  s.expect("the menu shows Robots and Displays") { LocationType.installable.map(&:plural_name) == %w[Robots Displays] }
  s.expect("Craft wire keeps its retired spool unit") { craft_wire.reload.stock_unit.retired? && craft_wire.unit == "spool" }
end
