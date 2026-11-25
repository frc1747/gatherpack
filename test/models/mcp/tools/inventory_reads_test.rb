require "test_helper"
require_relative "../../../support/mcp_orders_world"

# The inventory read tools show each viewer what the inventory pages show them, and refuse
# where the pages refuse.
class Mcp::Tools::InventoryReadsTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include McpOrdersWorld

  VIEWERS = %i[admin manager requester buyer builder outsider].freeze

  setup do
    StockMovement.record!(kind: :added, item: @stock.screws, location: @stock.bin, quantity: 4, person: @world.admin, reason: "Starting count")
    @paint = Item.create!(team: @world.art, name: "Paint", reorder_point: 1)
    @old = Item.create!(team: @world.club, name: "Old bracket", active: false)
    @robot = Location.create!(team: @world.robotics, name: "Robot", location_type: LocationType.installable.first)
    @motors = 3.times.map do |index|
      ItemUnit.create_with_event!(item: @stock.motor, location: @stock.bin, person: @world.admin).tap { |unit| unit.update!(code: "MOT-#{index + 1}") }
    end
    @motors.first.install!(into: @robot, by: @world.admin)
    @motors.second.mark_for_repair!(by: @world.admin, note: "Grinds")
    @items = [ @stock.screws, @stock.motor, @paint, @old ]
    @places = [ @stock.shop, @stock.cabinet, @stock.bin, @stock.art_room, @robot ]
  end

  def viewer(name)
    @world.public_send(name)
  end

  test "list_items lists the items the Items page lists to each viewer" do
    VIEWERS.each do |name|
      on_page = linked_on_page(viewer(name), inventory_items_path, @items) { |item| inventory_item_path(item) }
      result = call_as(viewer(name), "list_items", include_inactive: true, limit: 100)
      if on_page.nil?
        assert_equal "Not allowed", result.error, name
      else
        assert_equal on_page, ids_of(result), name
      end
    end

    assert_equal [ @stock.screws.neat_id ], ids_of(call_as(@world.requester, "list_items", query: "M4-12"))
    assert_equal [ @stock.screws.neat_id ], ids_of(call_as(@world.requester, "list_items", low_only: true))
    screws = call_as(@world.requester, "list_items", query: "screw").value["items"].first
    assert_equal [ 4, 10, true ], screws.values_at("total_stock", "reorder_point", "running_low")
    assert_equal 1, call_as(@world.requester, "list_items", query: "Motor").value["items"].first["total_stock"], "a tracked item counts available units"
    with_orders_settings(inventory_users: @world.art.name) do
      assert_equal "Not allowed", call_as(@world.requester, "list_items").error
    end
  end

  test "get_item opens for whoever the item page opens for, with stock by place and units" do
    VIEWERS.each do |name|
      @items.each do |item|
        status, = page_for(viewer(name), inventory_item_path(item))
        result = call_as(viewer(name), "get_item", item_id: item.neat_id)
        assert_equal status == 200, result.error.nil?, "#{name} #{item.name}"
      end
    end

    screws = call_as(@world.requester, "get_item", item_id: @stock.screws.neat_id).value
    assert_equal [ [ "Shop › Cabinet › Bin", 4 ] ], screws["stock"].map { |level| [ level["place"]["full_name"], level["quantity"] ] }
    assert_equal [ "Parts Depot" ], screws["sources"].map { |source| source["vendor_name"] }

    motor = call_as(@world.requester, "get_item", item_id: @stock.motor.neat_id).value
    assert_equal [ [ "Available", [ "MOT-3" ] ], [ "On Robot", [ "MOT-1" ] ], [ "In repair", [ "MOT-2" ] ] ],
      motor["units"].map { |group| [ group["group"], group["units"].map { |unit| unit["code"] } ] }
  end

  test "list_locations lists the places the Places page lists, with how many items are kept there" do
    VIEWERS.each do |name|
      on_page = linked_on_page(viewer(name), inventory_locations_path, @places) { |place| inventory_location_path(place) }
      result = call_as(viewer(name), "list_locations", limit: 100)
      if on_page.nil?
        assert_equal "Not allowed", result.error, name
      else
        assert_equal on_page, ids_of(result), name
      end
    end

    bin = call_as(@world.requester, "list_locations", parent_id: @stock.cabinet.neat_id).value["items"]
    assert_equal [ [ "Shop › Cabinet › Bin", "A-1", 1 ] ], bin.map { |place| place.values_at("full_name", "code", "items") }
  end

  test "reorder_list is the Reorder page, for inventory managers only" do
    VIEWERS.each do |name|
      status, = page_for(viewer(name), inventory_reorder_path)
      result = call_as(viewer(name), "reorder_list")
      assert_equal status == 200, result.error.nil?, name
    end

    groups = call_as(@world.buyer, "reorder_list").value["groups"]
    assert_equal [ "Parts Depot" ], groups.map { |group| group["vendor_name"] }
    row = groups.first["rows"].first
    assert_equal [ @stock.screws.neat_id, 16, "SCR-4" ], [ row["item"]["id"], row["suggested_quantity"], row["source"]["vendor_part_number"] ]
    assert_equal [ "Paint" ], call_as(@world.admin, "reorder_list", team_id: @world.art.neat_id).value["groups"].flat_map { |group| group["rows"].map { |r| r["item"]["name"] } }
  end

  test "list_machines and get_unit show what the machine and unit pages show" do
    VIEWERS.each do |name|
      on_page = linked_on_page(viewer(name), inventory_machine_type_path(@robot.location_type), [ @robot ]) { |machine| inventory_machine_path(machine) }
      result = call_as(viewer(name), "list_machines")
      if on_page.nil?
        assert_equal "Not allowed", result.error, name
      else
        assert_equal on_page, result.value["machines"].map { |machine| machine["id"] }.sort, name
      end

      status, = page_for(viewer(name), inventory_unit_path(@motors.second))
      assert_equal status == 200, call_as(viewer(name), "get_unit", unit_id: @motors.second.neat_id).error.nil?, name
    end

    machine = call_as(@world.requester, "list_machines").value["machines"].first
    assert_equal [ [ "MOT-1" ], 0 ], [ machine["units"].map { |unit| unit["code"] }, machine["flagged"] ]

    unit = call_as(@world.requester, "get_unit", code: "mot-2").value
    assert_equal [ @motors.second.neat_id, "needs_repair", "Shop › Cabinet › Bin" ], [ unit["id"], unit["condition"]["key"], unit["place"]["full_name"] ]
    assert_equal [ true, false ], unit["condition"].values_at("needs_attention", "out_of_service")
    assert_equal [ true, false ], unit["place"]["type"].values_at("holds_stock", "holds_installed_parts")
    assert_equal "Marked for repair New → Needs repair", unit["history"].first["text"]
    assert_equal %w[mark_for_repair tracked], unit["history"].map { |event| event["action"] }
    assert_equal %w[install move check], unit["actions"], "members don't mark repaired or retire"
    assert_includes call_as(@world.buyer, "get_unit", code: "MOT-2").value["actions"], "repaired"
    assert_equal "No part has the code NOPE", call_as(@world.requester, "get_unit", code: "NOPE").error
    assert_equal "No part has the code MOT-2", call_as(@world.outsider, "get_unit", code: "MOT-2").error, "another team's unit is looked for only among those you see"
  end

  test "list_machines covers every type that holds installed parts and names each type" do
    robot_type = @robot.location_type
    arm_type = LocationType.create!(name: "Arm", plural: "Arms", holds_stock: false, holds_installed_parts: true)
    arm = Location.create!(team: @world.robotics, name: "Arm 1", location_type: arm_type)

    result = call_as(@world.requester, "list_machines").value
    assert_equal [ "Machine", "Arm" ], result["types"].map { |type| type["name"] }
    assert_equal [ @robot, arm ].map(&:neat_id).sort, result["machines"].map { |machine| machine["id"] }.sort
    assert_equal [ arm_type.neat_id ], call_as(@world.requester, "list_machines", type_id: "Arm").value["machines"].map { |machine| machine["type"]["id"] }
    assert_equal [ @robot.neat_id ], call_as(@world.requester, "list_machines", type_id: robot_type.neat_id).value["machines"].map { |machine| machine["id"] }
    assert_match "isn't a type parts get installed on", call_as(@world.requester, "list_machines", type_id: "Storage").error

    robot_type.update!(name: "Robot", plural: "Robots")
    assert_equal "Robots", call_as(@world.requester, "list_machines").value["types"].first["plural"]

    arm_type.retire!
    assert_equal [ robot_type.neat_id ], call_as(@world.requester, "list_machines").value["types"].map { |type| type["id"] }
    assert_equal [ @robot.neat_id ], call_as(@world.requester, "list_machines").value["machines"].map { |machine| machine["id"] }
    assert_equal arm_type.neat_id, call_as(@world.requester, "list_locations", type_id: arm_type.neat_id).value["items"].first["type"]["id"],
      "a retired type's places are still places"
  end

  test "list_inventory_lists gives each picker's active rows to whoever may use inventory" do
    VIEWERS.each do |name|
      result = call_as(viewer(name), "list_inventory_lists")
      status, = page_for(viewer(name), inventory_items_path)
      assert_equal status == 200, result.error.nil?, name
    end

    lists = call_as(@world.requester, "list_inventory_lists").value
    assert_equal [ "Storage", "Machine" ], lists["place_types"].map { |type| type["name"] }
    assert_equal [ [ true, false ], [ false, true ] ], lists["place_types"].map { |type| type.values_at("holds_stock", "holds_installed_parts") }
    assert_equal [ "each" ], lists["stock_units"].select { |unit| unit["default"] }.map { |unit| unit["name"] }
    assert_equal %w[new good worn needs_repair broken], lists["part_conditions"].map { |condition| condition["key"] }.first(5)
    assert_equal %w[Hours Cycles Volts], lists["reading_types"].map { |type| type["name"] }
    assert_equal "h", lists["reading_types"].first["unit"]

    UnitCondition.find_by!(key: "broken").retire!
    assert_not_includes call_as(@world.requester, "list_inventory_lists").value["part_conditions"].map { |condition| condition["key"] }, "broken"
  end

  test "get_item and get_unit give the stock unit and reading types by ID" do
    hours = ReadingType.find_by!(key: "hours")
    @stock.motor.update!(reading_type_ids: [ hours.id ])
    item = call_as(@world.requester, "get_item", item_id: @stock.motor.neat_id).value
    assert_equal [ [ hours.neat_id, "Hours", "h" ] ], item["reading_types"].map { |type| type.values_at("id", "name", "unit") }
    assert_equal [ "each", true ], item["stock_unit"].values_at("name", "default")
    assert_equal "each", item["unit"]

    @motors.first.check!(by: @world.admin, readings: { "Hours" => 40 })
    unit = call_as(@world.requester, "get_unit", unit_id: @motors.first.neat_id).value
    assert_equal({ hours.neat_id => 40 }, unit["latest_readings"])
    assert_equal [ hours.neat_id ], unit["reading_types"].map { |type| type["id"] }
    assert_equal [ { hours.neat_id => 40 } ], unit["history"].map { |event| event["readings"] }.reject(&:empty?)
  end

  test "list_items pages with offset and says where the next page starts" do
    5.times { |index| Item.create!(team: @world.club, name: "Washer #{index}", reorder_point: 1) }
    first = call_as(@world.requester, "list_items", query: "Washer", limit: 2).value
    assert_equal [ [ "Washer 0", "Washer 1" ], true, 2 ], [ first["items"].map { |item| item["name"] }, first["truncated"], first["next_offset"] ]

    second = call_as(@world.requester, "list_items", query: "Washer", limit: 2, offset: first["next_offset"]).value
    assert_equal [ [ "Washer 2", "Washer 3" ], 4 ], [ second["items"].map { |item| item["name"] }, second["next_offset"] ]

    last = call_as(@world.requester, "list_items", query: "Washer", limit: 2, offset: 4).value
    assert_equal [ [ "Washer 4" ], false, nil ], [ last["items"].map { |item| item["name"] }, last["truncated"], last["next_offset"] ]

    low = call_as(@world.requester, "list_items", low_only: true, limit: 3, offset: 1).value
    assert_equal [ [ "Washer 0", "Washer 1", "Washer 2" ], 4 ], [ low["items"].map { |item| item["name"] }, low["next_offset"] ]
  end
end
