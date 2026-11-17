require "test_helper"
require "support/inventory_world"

class Inventory::UnitsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include InventoryWorld

  setup do
    host! "localhost"
    @world = build_inventory_world
    @motor = tracked_item!(@world, name: "Motor", units: 2, readings: [ { "name" => "Hours", "unit" => "h" } ])
    @unit, @other = @motor.item_units.order(:code).to_a
  end

  def as(person, **settings, &block)
    with_inventory(@world, **settings) do
      sign_in person.user
      block.call
    end
  end

  test "turns requests away while the feature is off" do
    with_settings(feature_inventory: "false") do
      sign_in @world.member.user
      get inventory_unit_path(@unit)
      assert_redirected_to root_path
    end
  end

  test "a member sees the unit page with the member actions only" do
    as(@world.member) do
      get inventory_unit_path(@unit)
      assert_response :success
      assert_select "h1", /MOT-1/
      assert_select "#unit_actions a", text: "Install"
      assert_select "#unit_actions a", text: "Move"
      assert_select "#unit_actions a", text: "Check"
      assert_select "#unit_actions a", text: "Mark for repair"
      assert_select "#unit_actions a", text: "Retire", count: 0
      assert_select "a", text: "Edit code and details", count: 0
    end
  end

  test "an inventory manager also sees Retire and edit" do
    as(@world.keeper) do
      get inventory_unit_path(@unit)
      assert_select "#unit_actions a", text: "Retire"
      assert_select "a", text: "Edit code and details"
    end
  end

  test "someone who can't see the item gets not found" do
    as(@world.outsider) do
      get inventory_unit_path(@unit)
      assert_response :not_found
    end
  end

  test "each action page renders for a manager" do
    as(@world.keeper) do
      %w[install take_off move check mark_for_repair retire].each do |act|
        get inventory_unit_action_form_path(@unit, act: act)
        assert_response :success, act
        assert_select "form#unit_action_form"
      end
      @unit.mark_for_repair!(by: @world.admin, note: "Noisy")
      get inventory_unit_action_form_path(@unit, act: "repaired")
      assert_response :success
    end
  end

  test "a member can't open a manager action's page" do
    as(@world.member) do
      get inventory_unit_action_form_path(@unit, act: "retire")
      assert_redirected_to root_path
      assert_equal "You are not allowed to do that", flash[:notice]
    end
  end

  test "a member installs a unit on a machine" do
    as(@world.member) do
      post install_inventory_unit_path(@unit), params: { location_id: @world.robot.id }
      assert_redirected_to inventory_unit_path(@unit)
      assert_equal @world.robot, @unit.reload.location
      assert_equal "install", @unit.events.last.action
      assert_equal @world.member, @unit.events.last.person
    end
  end

  test "installing a unit marked for repair asks first, then records the answer" do
    @unit.mark_for_repair!(by: @world.admin, note: "Noisy")
    as(@world.member) do
      post install_inventory_unit_path(@unit), params: { location_id: @world.robot.id }
      assert_response :unprocessable_entity
      assert_select "#install_question", /This unit is marked Needs repair: install anyway\?/
      assert_select "input[name=confirm][value='1']"
      assert_equal @world.bin1, @unit.reload.location

      post install_inventory_unit_path(@unit), params: { location_id: @world.robot.id, confirm: "1" }
      assert_redirected_to inventory_unit_path(@unit)
      assert_equal @world.robot, @unit.reload.location
      assert @unit.events.last.confirmed?
    end
  end

  test "installs a unit inside another one by its code" do
    as(@world.member) do
      post install_inventory_unit_path(@unit), params: { unit_code: "mot-2" }
      assert_redirected_to inventory_unit_path(@unit)
      assert_equal @other, @unit.reload.installed_in
    end
  end

  test "an unknown code is refused with a message" do
    as(@world.member) do
      post install_inventory_unit_path(@unit), params: { unit_code: "NOPE-1" }
      assert_equal "No part has the code NOPE-1", flash[:alert]
      assert_nil @unit.reload.installed_in
    end
  end

  test "takes a unit off a machine into a place" do
    @unit.install!(into: @world.robot, by: @world.admin)
    as(@world.member) do
      post take_off_inventory_unit_path(@unit), params: { location_id: @world.bin2.id }
      assert_redirected_to inventory_unit_path(@unit)
      assert_equal @world.bin2, @unit.reload.location
      assert_equal "Taken off, now in Bin 2", flash[:notice]
    end
  end

  test "moves a unit between places" do
    as(@world.member) do
      post move_inventory_unit_path(@unit), params: { location_id: @world.bin2.id }
      assert_equal @world.bin2, @unit.reload.location
    end
  end

  test "a check records the condition and readings, and the unit page shows them" do
    as(@world.member) do
      post check_inventory_unit_path(@unit), params: { condition: "worn", readings: { "Hours" => "12.5" }, note: "Bearing a bit loud" }
      assert_redirected_to inventory_unit_path(@unit)
      assert @unit.reload.condition_worn?
      assert_equal({ "Hours" => 12.5 }, @unit.events.last.readings)

      get inventory_unit_path(@unit)
      assert_select "#latest_readings dd", "12.5"
      assert_select "#readings_history tbody tr", 1
    end
  end

  test "mark for repair needs a note, and only a manager marks it repaired" do
    as(@world.member) do
      post mark_for_repair_inventory_unit_path(@unit), params: { condition: "broken", note: "" }
      assert_equal "Say what's wrong", flash[:alert]

      post mark_for_repair_inventory_unit_path(@unit), params: { condition: "broken", note: "Shaft snapped" }
      assert @unit.reload.condition_broken?

      post repaired_inventory_unit_path(@unit), params: { condition: "good", note: "New shaft" }
      assert_equal "You are not allowed to do that", flash[:notice]
      assert @unit.reload.condition_broken?
    end
    as(@world.keeper) do
      post repaired_inventory_unit_path(@unit), params: { condition: "good", note: "New shaft" }
      assert @unit.reload.condition_good?
    end
  end

  test "only a manager retires a unit" do
    as(@world.member) do
      post retire_inventory_unit_path(@unit), params: { note: "Worn out" }
      assert_not @unit.reload.condition_retired?
    end
    as(@world.keeper) do
      post retire_inventory_unit_path(@unit), params: { note: "Worn out" }
      assert @unit.reload.condition_retired?
    end
  end

  test "a manager edits a unit's code; a member can't" do
    as(@world.member) do
      get edit_inventory_unit_path(@unit)
      assert_redirected_to root_path
      patch inventory_unit_path(@unit), params: { item_unit: { code: "X-1" } }
      assert_equal "MOT-1", @unit.reload.code
    end
    as(@world.keeper) do
      get edit_inventory_unit_path(@unit)
      assert_response :success
      patch inventory_unit_path(@unit), params: { item_unit: { code: "NEO-07", serial_number: "SN123" } }
      assert_redirected_to inventory_unit_path(@unit)
      assert_equal [ "NEO-07", "SN123" ], [ @unit.reload.code, @unit.serial_number ]

      patch inventory_unit_path(@unit), params: { item_unit: { code: "mot-2" } }
      assert_response :unprocessable_entity
    end
  end

  test "a manager adds units to a tracked item" do
    as(@world.keeper) do
      get new_inventory_unit_path(item_id: @motor.id)
      assert_response :success
      assert_difference -> { @motor.item_units.count }, 3 do
        post inventory_units_path, params: { item_id: @motor.id, location_id: @world.bin2.id, count: 3, note: "Donated" }
      end
      assert_redirected_to inventory_item_path(@motor)
    end
  end

  test "a member can't add units" do
    as(@world.member) do
      assert_no_difference -> { ItemUnit.count } do
        post inventory_units_path, params: { item_id: @motor.id, location_id: @world.bin2.id, count: 3 }
      end
    end
  end

  test "finding a part by code opens it" do
    as(@world.member) do
      get inventory_units_path(code: "mot-1")
      assert_redirected_to inventory_unit_path(@unit)

      get inventory_units_path(code: "MOT")
      assert_response :success
      assert_select ".list-group-item", 2
    end
  end

  test "the recorder undoes their own action from the unit page" do
    as(@world.member) do
      post move_inventory_unit_path(@unit), params: { location_id: @world.bin2.id }
      get inventory_unit_path(@unit)
      assert_select "#unit_history button", text: "Undo"

      post undo_inventory_unit_event_path(@unit.events.last)
      assert_redirected_to inventory_unit_path(@unit)
      assert_equal @world.bin1, @unit.reload.location
    end
  end

  test "someone else can't undo a member's action" do
    @unit.move!(to: @world.bin2, by: @world.teammate)
    as(@world.member) do
      post undo_inventory_unit_event_path(@unit.events.last)
      assert_equal @world.bin2, @unit.reload.location
    end
  end

  test "inside another part by code prefers the unit's own team" do
    theirs = tracked_item!(@world, name: "Module", team: @world.robotics, units: 1).item_units.first
    ours = tracked_item!(@world, name: "Module", units: 1).item_units.first
    as(@world.member) do
      post install_inventory_unit_path(@unit), params: { unit_code: "MOD-1" }
      assert_equal ours, @unit.reload.installed_in
      assert_not_equal theirs, @unit.installed_in
    end
  end

  test "inside another part by its scanned label URL" do
    as(@world.member) do
      post install_inventory_unit_path(@unit), params: { unit_code: inventory_unit_url(@other, host: "localhost") }
      assert_equal @other, @unit.reload.installed_in
    end
  end
end
