require "test_helper"
require_relative "../../../support/mcp_orders_world"

# The inventory write tools record through StockMovement.record! and the ItemUnit actions, for
# whom the forms and the unit page allow.
class Mcp::Tools::InventoryWritesTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include McpOrdersWorld

  setup do
    StockMovement.record!(kind: :added, item: @stock.screws, location: @stock.bin, quantity: 12, person: @world.admin, reason: "Starting count")
    @drawer = Location.create!(parent: @stock.cabinet, name: "Drawer", code: "A-2")
    @robot = Location.create!(team: @world.robotics, name: "Robot", location_type: LocationType.installable.first)
    @unit = ItemUnit.create_with_event!(item: @stock.motor, location: @stock.bin, person: @world.admin).tap { |unit| unit.update!(code: "MOT-1") }
  end

  test "record_stock_movement records what a member's forms allow, with the form's default place" do
    used = call_as(@world.requester, "record_stock_movement", kind: "used", item_id: @stock.screws.neat_id, quantity: 3, reason: "Gearbox")
    assert_nil used.error
    assert_equal [ "used", -3, 9, 9, "Shop › Cabinet › Bin" ], used.value.values_at("kind", "quantity", "stock_after", "total_after").push(used.value["location"]["full_name"])
    assert_equal [ @world.requester, "Gearbox" ], StockMovement.find_by_neat_id(used.value["id"]).then { |movement| [ movement.person, movement.reason ] }

    moved = call_as(@world.requester, "record_stock_movement", kind: "moved", item_id: @stock.screws.neat_id, quantity: 4,
      to_location_id: @drawer.neat_id)
    assert_equal [ 5, 4 ], moved.value.values_at("stock_after", "to_stock_after")

    counted = call_as(@world.requester, "record_stock_movement", kind: "counted", item_id: @stock.screws.neat_id,
      location_id: @stock.bin.neat_id, quantity: 2)
    assert_equal [ -3, 2, 2 ], counted.value.values_at("quantity", "counted_quantity", "stock_after")
  end

  test "record_stock_movement refuses kinds and items the forms refuse" do
    assert_equal "Not allowed", call_as(@world.requester, "record_stock_movement", kind: "added", item_id: @stock.screws.neat_id,
      quantity: 5, reason: "Found").error, "members record only inventory_member_kinds"
    with_orders_settings(inventory_member_kinds: "used") do
      assert_equal "Not allowed", call_as(@world.requester, "record_stock_movement", kind: "counted", item_id: @stock.screws.neat_id, quantity: 5).error
    end
    assert_equal "Not found", call_as(@world.outsider, "record_stock_movement", kind: "used", item_id: @stock.screws.neat_id).error
    assert_not_nil call_as(@world.buyer, "record_stock_movement", kind: "added", item_id: @stock.screws.neat_id, quantity: 5).error, "added needs a reason"
    assert_not_nil call_as(@world.buyer, "record_stock_movement", kind: "used", item_id: @stock.motor.neat_id, location_id: @stock.bin.neat_id).error,
      "a tracked item's stock is its units"

    added = call_as(@world.buyer, "record_stock_movement", kind: "added", item_id: @stock.screws.neat_id, quantity: 5, reason: "Found a box")
    assert_equal 17, added.value["total_after"]
  end

  test "record_unit_event takes the unit page's actions for whom it allows them" do
    installed = call_as(@world.requester, "record_unit_event", unit_id: @unit.neat_id, action: "install", location_id: @robot.neat_id)
    assert_nil installed.error
    assert_equal [ "Robot", "Installed on Robot" ], [ installed.value["place"]["full_name"], installed.value["event"]["text"] ]

    assert_equal "Not allowed", call_as(@world.requester, "record_unit_event", unit_id: @unit.neat_id, action: "retire", note: "Old").error
    assert_equal "Not found", call_as(@world.outsider, "record_unit_event", unit_id: @unit.neat_id, action: "check").error

    checked = call_as(@world.requester, "record_unit_event", unit_id: @unit.neat_id, action: "mark_for_repair", note: "Grinds")
    assert_equal "needs_repair", checked.value["unit"]["condition"]["key"]
    assert_equal "Say what was done", call_as(@world.buyer, "record_unit_event", unit_id: @unit.neat_id, action: "repaired").error

    assert_nil call_as(@world.requester, "record_unit_event", unit_id: @unit.neat_id, action: "take_off").error
    question = call_as(@world.requester, "record_unit_event", unit_id: @unit.neat_id, action: "install", location_id: @robot.neat_id)
    assert_match "This unit is marked Needs repair: install anyway?", question.error
    anyway = call_as(@world.requester, "record_unit_event", unit_id: @unit.neat_id, action: "install", location_id: @robot.neat_id, confirm: true)
    assert_nil anyway.error
    assert_equal true, @unit.events.reload.last.confirmed?
  end

  test "record_unit_event records a check's readings, and refuses a reading the item doesn't ask for" do
    hours = ReadingType.find_by!(key: "hours")
    @stock.motor.update!(reading_type_ids: [ hours.id ])
    checked = call_as(@world.requester, "record_unit_event", unit_id: @unit.neat_id, action: "check", condition: "worn", readings: { "Hours" => 12.5 })
    assert_nil checked.error
    assert_equal({ hours.neat_id => 12.5 }, call_as(@world.requester, "get_unit", unit_id: @unit.neat_id).value["latest_readings"])
    by_id = call_as(@world.requester, "record_unit_event", unit_id: @unit.neat_id, action: "check", readings: { hours.neat_id => 14 })
    assert_nil by_id.error
    assert_equal({ hours.neat_id => 14 }, call_as(@world.requester, "get_unit", unit_id: @unit.neat_id).value["latest_readings"])
    assert_not_nil call_as(@world.requester, "record_unit_event", unit_id: @unit.neat_id, action: "check", readings: { "Volts" => 12 }).error
  end

  test "record_unit_event takes a condition by ID, key or name and follows the group's list" do
    worn = UnitCondition.find_by!(key: "worn")
    assert_equal "worn", call_as(@world.requester, "record_unit_event", unit_id: @unit.neat_id, action: "check", condition: worn.neat_id).value["unit"]["condition"]["key"]
    worn.update!(name: "Tired")
    assert_equal "Tired", call_as(@world.requester, "record_unit_event", unit_id: @unit.neat_id, action: "check", condition: "tired").value["unit"]["condition"]["name"]
    assert_equal "No part condition is \"Weathered\"", call_as(@world.requester, "record_unit_event", unit_id: @unit.neat_id, action: "check", condition: "Weathered").error

    custom = UnitCondition.create!(name: "Sticky", needs_attention: true)
    marked = call_as(@world.requester, "record_unit_event", unit_id: @unit.neat_id, action: "mark_for_repair", condition: custom.neat_id, note: "Sticks")
    assert_equal [ "Sticky", true ], marked.value["unit"]["condition"].values_at("name", "needs_attention")
    assert_equal "Pick a condition", call_as(@world.requester, "record_unit_event", unit_id: @unit.neat_id, action: "check", condition: "retired").error
    assert_match "Pick", call_as(@world.requester, "record_unit_event", unit_id: @unit.neat_id, action: "mark_for_repair", condition: "good", note: "x").error
  end

  test "record_unit_event asks for the places the group's types allow" do
    assert_match "Give a machine", call_as(@world.requester, "record_unit_event", unit_id: @unit.neat_id, action: "install").error
    @robot.location_type.update!(name: "Robot", plural: "Robots")
    assert_match "Give a robot", call_as(@world.requester, "record_unit_event", unit_id: @unit.neat_id, action: "install").error
  end
end
