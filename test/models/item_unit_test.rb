require "test_helper"
require "support/inventory_world"

class ItemUnitTest < ActiveSupport::TestCase
  include InventoryWorld

  setup do
    @world = build_inventory_world
    @motor = tracked_item!(@world, name: "Motor", units: 4, reorder_point: 2)
    @units = @motor.item_units.order(:code).to_a
  end

  test "available excludes installed, needs repair, broken and retired units, and drives the reorder list" do
    with_inventory(@world) do
      assert_equal 4, @motor.total_stock
      assert_not @motor.on_reorder_list?

      @units[0].install!(into: @world.robot, by: @world.member)
      @units[1].mark_for_repair!(by: @world.member, note: "Grinding")
      assert_equal 2, @motor.total_stock
      assert @motor.on_reorder_list?

      @units[2].mark_for_repair!(by: @world.member, note: "Smoked", condition: "broken")
      @units[3].retire!(by: @world.keeper, note: "Too old")
      assert_equal 0, @motor.total_stock
      assert_includes Inventory::Reorder.new(@world.keeper).rows.map { |row| row.item.name }, "Motor"
    end
  end

  test "a tracked item has no movements of its own" do
    with_inventory(@world) do
      assert_raises(Inventory::Refused) { record(@world, :added, 1, item: @motor, reason: "Found") }
    end
  end

  test "installing an outer unit carries its inner units and writes an event for each" do
    with_inventory(@world) do
      modules = tracked_item!(@world, name: "Module", units: 1)
      outer = modules.item_units.first
      @units[0].install!(into: outer, by: @world.member)
      @units[1].install!(into: outer, by: @world.member)

      assert_equal [ @world.bin1, @world.bin1 ], [ @units[0].reload.location, @units[1].reload.location ]
      assert_not @units[0].available?

      event = outer.install!(into: @world.robot, by: @world.member)

      [ @units[0], @units[1] ].each do |inner|
        inner.reload
        assert_equal @world.robot, inner.location
        assert_equal outer, inner.installed_in
        carried = inner.events.last
        assert_equal [ "install", outer, @world.bin1, @world.robot ], [ carried.action, carried.via_unit, carried.from_location, carried.to_location ]
      end
      assert_equal 2, ItemUnitEvent.where(via_unit: outer, created_at: event.created_at..).count
      assert_equal [ outer ], @world.robot.mounted_units.to_a
      assert_equal [ outer, @units[0], @units[1] ].map(&:id).sort, ItemUnit.installed.ids.sort
      assert_equal [ @units[0], @units[1] ].map(&:id).sort, outer.all_contents.map(&:id).sort

      @units[0].reload.take_off!(by: @world.member, to: @world.bin2)
      assert_nil @units[0].reload.installed_in
      assert_equal @world.bin2, @units[0].location
    end
  end

  test "a unit can't go inside itself or one of its own contents" do
    with_inventory(@world) do
      @units[1].install!(into: @units[0], by: @world.member)

      assert_raises(Inventory::Refused) { @units[0].install!(into: @units[0], by: @world.member) }
      assert_raises(Inventory::Refused) { @units[0].install!(into: @units[1].reload, by: @world.member) }
    end
  end

  test "a retired unit can't be installed" do
    with_inventory(@world) do
      @units[0].retire!(by: @world.keeper, note: "Burnt out")

      error = assert_raises(Inventory::Refused) { @units[0].install!(into: @world.robot, by: @world.keeper, confirm: true) }
      assert_equal "A retired unit can't be installed", error.message
    end
  end

  test "installing a unit needing repair needs the confirm and records it" do
    with_inventory(@world) do
      @units[0].mark_for_repair!(by: @world.member, note: "Noisy bearing")

      error = assert_raises(Inventory::ConfirmNeeded) { @units[0].install!(into: @world.robot, by: @world.member) }
      assert_equal "This unit is marked Needs repair: install anyway?", error.message
      assert_equal @world.bin1, @units[0].reload.location

      event = @units[0].install!(into: @world.robot, by: @world.member, confirm: true)
      assert event.confirmed?
      assert_not @units[1].install!(into: @world.robot, by: @world.member).confirmed?
    end
  end

  test "members can't take actions outside inventory_member_unit_actions" do
    with_inventory(@world) do
      @units[0].mark_for_repair!(by: @world.member, note: "Noisy")

      assert_raises(Inventory::Refused) { @units[0].repaired!(by: @world.member, note: "New bearing") }
      assert_raises(Inventory::Refused) { @units[1].retire!(by: @world.member, note: "Old") }
      assert_raises(Inventory::Refused) { @units[0].check!(by: @world.member, condition: "good") }
      assert @units[0].repaired!(by: @world.keeper, note: "New bearing")
      assert_equal "good", @units[0].reload.unit_condition.key
    end

    with_inventory(@world, inventory_member_unit_actions: "check") do
      assert_raises(Inventory::Refused) { @units[1].move!(to: @world.bin2, by: @world.member) }
      assert @units[1].check!(by: @world.member, condition: "worn")
    end
  end

  test "someone outside the item's teams can't act on it" do
    with_inventory(@world) do
      assert_raises(Inventory::Refused) { @units[0].move!(to: @world.bin2, by: @world.outsider) }
    end
  end

  test "undo writes a reversing event and puts the unit back" do
    with_inventory(@world) do
      install = @units[0].install!(into: @world.robot, by: @world.member)
      reversal = install.undo!(by: @world.member)

      assert_equal install, reversal.reverses
      assert_equal "install", reversal.action
      assert_equal @world.bin1, @units[0].reload.location
      assert install.reload.undone?
      assert_not install.undoable_by?(@world.keeper)

      check = @units[1].mark_for_repair!(by: @world.member, note: "Loose wire")
      check.undo!(by: @world.keeper)
      assert_equal "new", @units[1].reload.unit_condition.key
      assert ItemUnitEvent.exists?(check.id)
    end
  end

  test "undo is for the recorder within the undo minutes, managers any time, and only the latest action" do
    with_inventory(@world) do
      move = @units[0].move!(to: @world.bin2, by: @world.member)
      assert_not move.undoable_by?(@world.teammate)

      travel 11.minutes do
        assert_not move.undoable_by?(@world.member)
        assert move.undoable_by?(@world.keeper)
      end

      @units[0].reload.check!(by: @world.member, note: "Fine")
      assert_not move.undoable_by?(@world.keeper), "not its latest event"
    end
  end

  test "a second undo is refused, even from a copy that checked before the first landed" do
    with_inventory(@world) do
      move = @units[0].move!(to: @world.bin2, by: @world.member)
      stale = ItemUnitEvent.find(move.id)
      assert stale.undoable_by?(@world.member)

      move.undo!(by: @world.member)
      assert_raises(Inventory::Refused) { stale.undo!(by: @world.member) }
      assert_equal 1, ItemUnitEvent.where(reverses_id: move.id).count
      assert_equal @world.bin1, @units[0].reload.location
    end
  end

  test "deleting a person keeps unit history and blanks who did it" do
    with_inventory(@world) do
      event = @units[0].move!(to: @world.bin2, by: @world.member, recorded_by: @world.keeper)
      @world.member.destroy!
      @world.keeper.destroy!

      event = ItemUnitEvent.find(event.id)
      assert_nil event.person_id
      assert_nil event.recorded_by_id
      assert_equal @world.bin2, @units[0].reload.location
    end
  end

  test "undoing an outer unit's install carries its contents back" do
    with_inventory(@world) do
      @units[1].install!(into: @units[0], by: @world.member)
      install = @units[0].reload.install!(into: @world.robot, by: @world.member)
      install.undo!(by: @world.member)

      assert_equal [ @world.bin1, @world.bin1 ], [ @units[0].reload.location, @units[1].reload.location ]
      assert_equal @units[0], @units[1].installed_in
    end
  end

  test "events can't be updated or destroyed" do
    with_inventory(@world) do
      event = @units[0].move!(to: @world.bin2, by: @world.member)

      assert_raises(ActiveRecord::ReadOnlyRecord) { event.update!(note: "changed") }
      assert_raises(ActiveRecord::ReadOnlyRecord) { event.destroy }
      assert_raises(ActiveRecord::ReadOnlyRecord) { event.delete }
    end
  end

  test "a check records the condition and the item's readings" do
    with_inventory(@world) do
      battery = tracked_item!(@world, name: "Battery", units: 1,
        readings: [ { "name" => "Internal resistance", "unit" => "mΩ" }, { "name" => "Charge cycles" } ])
      unit = battery.item_units.first
      unit.check!(by: @world.member, condition: "good", readings: { "Internal resistance" => "14.5", "Charge cycles" => "" })
      unit.check!(by: @world.member, condition: "worn", readings: { "Charge cycles" => "212" }, note: "Getting tired")

      assert_equal "worn", unit.reload.unit_condition.key
      assert_equal "Getting tired", unit.condition_note
      resistance, cycles = battery.reading_types.to_a
      assert_equal({ resistance.id => 14.5, cycles.id => 212 }, unit.latest_readings)
      assert_raises(Inventory::Refused) { unit.check!(by: @world.member, readings: { "Voltage" => "12" }) }
      assert_raises(Inventory::Refused) { unit.check!(by: @world.member, readings: { "Charge cycles" => "lots" }) }
      assert_raises(Inventory::Refused) { unit.check!(by: @world.member, condition: "retired") }
    end
  end

  test "a check can carry a photo" do
    with_inventory(@world) do
      event = @units[0].check!(by: @world.member, photo: { io: StringIO.new("photo"), filename: "unit.jpg", content_type: "image/jpeg" })

      assert event.reload.photo.attached?
    end
  end

  test "turning tracking on creates units for existing stock; turning it off is refused while units exist" do
    with_inventory(@world) do
      stock!(@world, 3)
      stock!(@world, 2, location: @world.bin2)
      record(@world, :used, 1, location: @world.bin2)

      @world.screws.start_tracking!(by: @world.keeper)

      assert @world.screws.reload.tracked?
      assert_equal({ @world.bin1.id => 3, @world.bin2.id => 1 }, @world.screws.item_units.group(:location_id).count)
      assert_equal 0, StockMovement.where(item: @world.screws).group(:location_id).sum(:quantity).values.sum
      assert_equal 4, @world.screws.total_stock
      assert_raises(Inventory::Refused) { @world.screws.stop_tracking!(by: @world.keeper) }
      assert_not @world.screws.update(tracked: false)

      plain = Item.create!(team: @world.club, name: "Washer", home_location: @world.bin1)
      stock!(@world, 5, item: plain)
      assert_not plain.update(tracked: true), "turning tracking on goes through start_tracking!"
      assert_includes plain.errors[:tracked].first, "start_tracking!"
      assert_not plain.reload.tracked?
      assert_equal 5, plain.total_stock

      bare = Item.create!(team: @world.club, name: "Gearbox")
      bare.start_tracking!(by: @world.keeper)
      bare.stop_tracking!(by: @world.keeper)
      assert_not bare.reload.tracked?
      assert_raises(Inventory::Refused) { bare.start_tracking!(by: @world.member) }
    end
  end

  test "codes are unique within a team" do
    with_inventory(@world) do
      @units[1].code = @units[0].code.downcase
      assert_not @units[1].valid?

      other = tracked_item!(@world, name: "Gearbox", team: @world.art)
      assert ItemUnit.new(item: other, location: @world.bin1, code: @units[0].code).valid?
    end
  end

  test "receive creates units with blank codes" do
    with_inventory(@world) do
      units = ItemUnit.receive!(item: @motor, location: @world.bin2, count: 3, person: @world.keeper, note: "From the order")

      assert_equal 3, units.size
      assert units.all? { |unit| unit.code.nil? && unit.events.first.action == "received" }
      assert_equal 7, @motor.total_stock
      assert_raises(Inventory::Refused) { ItemUnit.receive!(item: @motor, location: @world.bin2, count: 1, person: @world.member) }
      assert_raises(Inventory::Refused) { ItemUnit.receive!(item: @world.screws, location: @world.bin2, count: 1, person: @world.keeper) }

      old_shelf = Location.create!(team: @world.club, name: "Old shelf", active: false)
      error = assert_raises(Inventory::Refused) do
        ItemUnit.receive!(item: @motor, location: old_shelf, count: 2, person: @world.keeper, authorized_by: @world.admin)
      end
      assert_equal "Old shelf isn't active", error.message
      assert_equal 7, @motor.item_units.count
    end
  end

  test "the needs_repair, installed and removed hooks fire once" do
    with_inventory(@world) do
      record_hooks(*Inventory::UNIT_EVENTS.values)
      unit = @units[0]
      unit.mark_for_repair!(by: @world.member, note: "Noisy")
      unit.mark_for_repair!(by: @world.member, note: "Now broken", condition: "broken")
      unit.install!(into: @world.robot, by: @world.member, confirm: true)
      cart = Location.create!(team: @world.robotics, name: "Cart")
      other_robot = Location.create!(team: @world.robotics, parent: cart, name: "Practice robot", location_type: location_type("machine"))
      unit.reload.install!(into: other_robot, by: @world.member, confirm: true)
      unit.reload.take_off!(by: @world.member)

      assert_equal [ [ "item_units - needs_repair", unit.id ], [ "item_units - installed", unit.id ], [ "item_units - removed", unit.id ] ],
        hook_log
    end
  end

  test "the item's stock hooks fire when units change what's available" do
    with_inventory(@world) do
      record_hooks(*Inventory::ITEM_EVENTS.values)
      @units[0].install!(into: @world.robot, by: @world.member)
      @units[1].install!(into: @world.robot, by: @world.member)
      @units[2].install!(into: @world.robot, by: @world.member)

      assert_equal [ [ "items - running_low", @motor.id ] ], hook_log
    end
  end

  test "nothing fires with the flag off" do
    with_inventory(@world, feature_inventory: "false") do
      record_hooks(*Inventory::HOOK_EVENTS)
      @units[0].mark_for_repair!(by: @world.admin, note: "x")
      @units[1].install!(into: @world.robot, by: @world.admin)

      assert_empty hook_log
    end
  end
end
