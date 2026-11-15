require "test_helper"
require "support/inventory_world"

class StockMovementTest < ActiveSupport::TestCase
  include InventoryWorld
  include ActiveJob::TestHelper

  setup { @world = build_inventory_world }

  def level(item: @world.screws, location: @world.bin1)
    StockLevel.find_by(item: item, location: location)&.quantity
  end

  def sum(item: @world.screws, location: @world.bin1)
    StockMovement.where(item: item, location: location).sum(:quantity)
  end

  test "stock is the sum of movements and the level matches after every kind" do
    with_inventory(@world) do
      stock!(@world, 20)
      record(@world, :received, 5, reason: "Parts Depot")
      record(@world, :used, 3)
      record(@world, :removed, 2, reason: "Stripped")
      record(@world, :moved, 4, to_location: @world.bin2)
      record(@world, :counted, 15)

      assert_equal 15, sum
      assert_equal 15, level
      assert_equal 4, sum(location: @world.bin2)
      assert_equal 4, level(location: @world.bin2)
      assert_equal 19, @world.screws.total_stock
      assert_equal %w[added received used removed moved counted],
        StockMovement.where(item: @world.screws, location: @world.bin1).order(:created_at).pluck(:kind)
    end
  end

  test "used and removed take stock out; received and added put it in" do
    with_inventory(@world) do
      assert_equal 7, stock!(@world, 7).quantity
      assert_equal(-2, record(@world, :used, 2).quantity)
      assert_equal(-1, record(@world, :removed, 1, reason: "Lost").quantity)
      assert_equal 3, record(@world, :received, 3).quantity
    end
  end

  test "used defaults to one from the item's home location" do
    with_inventory(@world) do
      stock!(@world, 5)
      movement = StockMovement.record!(kind: :used, item: @world.screws, person: @world.member)

      assert_equal @world.bin1, movement.location
      assert_equal(-1, movement.quantity)
      assert_equal 4, level
    end
  end

  test "without a home location, used takes the only place with stock" do
    with_inventory(@world) do
      @world.screws.update!(home_location: nil)
      stock!(@world, 5, location: @world.bin2)

      assert_equal @world.bin2, StockMovement.record!(kind: :used, item: @world.screws, person: @world.member).location
    end
  end

  test "a count writes counted minus current, and a count that matches writes zero" do
    with_inventory(@world) do
      stock!(@world, 10)
      fewer = record(@world, :counted, 7, person: @world.member)
      same = record(@world, :counted, 7, person: @world.member)

      assert_equal(-3, fewer.quantity)
      assert_equal 7, fewer.counted_quantity
      assert_equal 0, same.quantity
      assert_equal 7, same.counted_quantity
      assert_equal 7, level
      assert_equal same.created_at, @world.screws.last_counted_at
      assert_equal same.created_at, @world.bin1.last_counted_at
    end
  end

  test "a move writes two rows with one group, and its undo reverses both" do
    with_inventory(@world) do
      stock!(@world, 10)
      out = record(@world, :moved, 4, to_location: @world.bin2, person: @world.member)
      rows = out.move_rows

      assert_equal [ -4, 4 ], rows.map(&:quantity)
      assert_equal [ @world.bin1, @world.bin2 ], rows.map(&:location)
      assert_equal 1, rows.map(&:move_group_id).uniq.size

      out.undo!(by: @world.member)

      assert_equal 10, level
      assert_equal 0, level(location: @world.bin2)
      assert_equal 2, StockMovement.where(reverses_id: rows.map(&:id)).count
      assert out.reload.undone?
      assert rows.last.reload.undone?
    end
  end

  test "a move without a quantity takes all of it" do
    with_inventory(@world) do
      stock!(@world, 6)
      record(@world, :moved, to_location: @world.bin2)

      assert_equal 0, level
      assert_equal 6, level(location: @world.bin2)
    end
  end

  test "the recorder can undo within the undo minutes but not after; a manager any time; the original stays" do
    with_inventory(@world, inventory_undo_minutes: "10") do
      stock!(@world, 10)
      used = record(@world, :used, 2, person: @world.member)
      later = record(@world, :used, 1, person: @world.member)

      assert used.undoable_by?(@world.member)
      assert_not used.undoable_by?(@world.teammate)
      reversal = used.undo!(by: @world.member)

      assert_equal 2, reversal.quantity
      assert_equal "used", reversal.kind
      assert_equal used, reversal.reverses
      assert StockMovement.exists?(used.id)
      assert_not used.reload.undoable_by?(@world.member), "already undone"
      assert_not reversal.undoable_by?(@world.admin), "a reversal can't be undone"

      travel 11.minutes do
        assert_not later.undoable_by?(@world.member)
        assert_raises(Inventory::Refused) { later.undo!(by: @world.member) }
        assert later.undoable_by?(@world.keeper)
        later.undo!(by: @world.keeper)
      end
      assert_equal 10, level
    end
  end

  test "a second undo is refused, even from a copy that checked before the first landed" do
    with_inventory(@world) do
      stock!(@world, 10)
      used = record(@world, :used, 3, person: @world.member)
      stale = StockMovement.find(used.id)
      assert stale.undoable_by?(@world.member)

      used.undo!(by: @world.member)
      error = assert_raises(Inventory::Refused) { stale.undo!(by: @world.member) }
      assert_equal "This change can't be undone", error.message
      assert_equal 1, StockMovement.where(reverses_id: used.id).count
      assert_equal 10, level
    end
  end

  test "a movement can be reversed only once in the database too" do
    with_inventory(@world) do
      used = record(@world, :used, 1)
      StockMovement.create!(kind: "used", item: @world.screws, location: @world.bin1, quantity: 1, reverses: used)

      assert_raises(ActiveRecord::RecordNotUnique) do
        StockMovement.create!(kind: "used", item: @world.screws, location: @world.bin1, quantity: 1, reverses: used)
      end
    end
  end

  test "deleting a person keeps their changes and blanks who made them" do
    with_inventory(@world) do
      stock!(@world, 10)
      used = record(@world, :used, 2, person: @world.member, recorded_by: @world.keeper)
      @world.member.destroy!
      @world.keeper.destroy!

      used = StockMovement.find(used.id)
      assert_nil used.person_id
      assert_nil used.recorded_by_id
      assert_equal 8, level
      assert_equal 8, sum
      assert_not used.undoable_by?(@world.teammate)
    end
  end

  test "undoing a count reverses its difference" do
    with_inventory(@world) do
      stock!(@world, 10)
      count = record(@world, :counted, 4)
      count.undo!(by: @world.admin)

      assert_equal 10, level
    end
  end

  test "movements can't be updated or destroyed" do
    with_inventory(@world) do
      movement = stock!(@world, 5)

      assert_raises(ActiveRecord::ReadOnlyRecord) { movement.update!(quantity: 50) }
      assert_raises(ActiveRecord::ReadOnlyRecord) { movement.destroy }
      assert_raises(ActiveRecord::ReadOnlyRecord) { movement.delete }
      assert_equal 5, StockMovement.find(movement.id).quantity
    end
  end

  test "going below zero is allowed, flags the place, and counts as zero in the total" do
    with_inventory(@world) do
      stock!(@world, 2)
      stock!(@world, 5, location: @world.bin2)
      record(@world, :used, 4, person: @world.member)

      assert_equal(-2, level)
      assert @world.bin1.needs_count?
      assert_not @world.bin2.needs_count?
      assert_equal 5, @world.screws.total_stock
    end
  end

  test "stock in an inactive place isn't in the total" do
    with_inventory(@world) do
      stock!(@world, 5)
      other = Location.create!(team: @world.club, name: "Old shelf")
      stock!(@world, 3, location: other)
      assert_equal 8, @world.screws.total_stock

      other.update_columns(active: false)
      assert_equal 5, @world.screws.total_stock
    end
  end

  test "members record the kinds in inventory_member_kinds; they can't record removed by default" do
    with_inventory(@world) do
      stock!(@world, 10)
      %i[used counted].each { |kind| assert record(@world, kind, 1, person: @world.member) }
      assert record(@world, :moved, 1, to_location: @world.bin2, person: @world.member)

      error = assert_raises(Inventory::Refused) { record(@world, :removed, 1, reason: "Lost", person: @world.member) }
      assert_match "can't record removed", error.message
      assert_raises(Inventory::Refused) { record(@world, :received, 1, person: @world.member) }
      assert record(@world, :removed, 1, reason: "Lost", person: @world.keeper)
    end

    with_inventory(@world, inventory_member_kinds: "used") do
      assert_raises(Inventory::Refused) { record(@world, :counted, 3, person: @world.member) }
    end
  end

  test "someone who can't see the item or place can't record" do
    with_inventory(@world) do
      art_shelf = Location.create!(team: @world.art, name: "Art shelf")

      assert_raises(Inventory::Refused) { record(@world, :used, 1, person: @world.outsider) }
      assert_raises(Inventory::Refused) { record(@world, :used, 1, location: art_shelf, person: @world.member) }
    end
  end

  test "authorized_by skips the permission check for another feature's own decision" do
    with_inventory(@world) do
      movement = record(@world, :received, 4, person: @world.member, authorized_by: @world.admin)

      assert_equal 4, movement.quantity
    end
  end

  test "a manager can enter a change for someone else" do
    with_inventory(@world) do
      movement = record(@world, :used, 1, person: @world.member, recorded_by: @world.keeper)

      assert_equal @world.member, movement.person
      assert_equal @world.keeper, movement.recorded_by
      assert movement.undoable_by?(@world.keeper)
    end
  end

  test "added and removed need a reason; used does when inventory_used_needs_reason is on" do
    with_inventory(@world) do
      assert_raises(Inventory::Refused) { record(@world, :added, 3) }
      assert_raises(Inventory::Refused) { record(@world, :removed, 1, reason: " ") }
      assert record(@world, :used, 1)
    end
    with_inventory(@world, inventory_used_needs_reason: "true") do
      error = assert_raises(Inventory::Refused) { record(@world, :used, 1) }
      assert_equal "Say what it was for", error.message
      assert record(@world, :used, 1, reason: "Drivetrain")
    end
  end

  test "quantities are whole numbers above zero" do
    with_inventory(@world) do
      [ 0, -2, "1.5", "lots" ].each do |quantity|
        assert_raises(Inventory::Refused, quantity.inspect) { record(@world, :received, quantity) }
      end
      stock!(@world, 8)
      [ "2.5", "3x", 2.5, "lots" ].each do |quantity|
        assert_no_difference -> { StockMovement.count } do
          assert_raises(Inventory::Refused, quantity.inspect) { record(@world, :used, quantity) }
          assert_raises(Inventory::Refused, quantity.inspect) { record(@world, :moved, quantity, to_location: @world.bin2) }
          assert_raises(Inventory::Refused, quantity.inspect) { record(@world, :counted, quantity) }
        end
      end
      assert_equal 8, level
      assert_raises(Inventory::Refused) { record(@world, :counted, -1) }
      assert_equal 3, record(@world, :received, "3").quantity
    end
  end

  test "a tracked item, a machine, an inactive item or place, and a move to the same place are refused" do
    with_inventory(@world) do
      motor = tracked_item!(@world)
      assert_raises(Inventory::Refused) { record(@world, :added, 1, item: motor, reason: "x") }
      assert_raises(Inventory::Refused) { record(@world, :added, 1, location: @world.robot, reason: "x") }
      assert_raises(Inventory::Refused) { record(@world, :moved, 1, to_location: @world.bin1) }
      assert_raises(Inventory::Refused) { record(@world, :moved, 1) }
      @world.screws.update!(active: false)
      assert_raises(Inventory::Refused) { record(@world, :added, 1, reason: "x") }
    end
  end

  test "hook events fire once on each crossing and not again while low" do
    with_inventory(@world) do
      record_hooks(*Inventory::ITEM_EVENTS.values, Inventory::COUNT_DIFFERS_EVENT)
      stock!(@world, 12)
      assert_equal [ [ "items - restocked", @world.screws.id ] ], hook_log, "from nothing to above the reorder point"

      hook_log.clear
      record(@world, :used, 2) # 10: on the list
      record(@world, :used, 3) # 7: still low
      assert_equal [ [ "items - running_low", @world.screws.id ] ], hook_log

      hook_log.clear
      record(@world, :used, 7) # 0
      record(@world, :used, 1) # -1, still zero in the total
      assert_equal [ [ "items - out_of_stock", @world.screws.id ] ], hook_log

      hook_log.clear
      record(@world, :received, 20)
      assert_equal [ [ "items - restocked", @world.screws.id ] ], hook_log.sort

      hook_log.clear
      count = record(@world, :counted, 15)
      record(@world, :counted, 15)
      assert_equal [ [ "stock_movements - count_differs", count.id ] ], hook_log
    end
  end

  test "nothing fires with the flag off" do
    with_inventory(@world, feature_inventory: "false") do
      record_hooks(*Inventory::HOOK_EVENTS)
      events = []
      subscriber = ActiveSupport::Notifications.subscribe("stock_movement_recorded.gatherpack") { |*args| events << args }
      stock!(@world, 12)
      record(@world, :used, 12)
      record(@world, :counted, 3)

      assert_empty hook_log
      assert_empty events
    ensure
      ActiveSupport::Notifications.unsubscribe(subscriber)
    end
  end

  test "stock_movement_recorded is published after commit with the documented payload" do
    with_inventory(@world) do
      stock!(@world, 11)
      payloads = []
      subscriber = ActiveSupport::Notifications.subscribe("stock_movement_recorded.gatherpack") do |*, payload|
        payloads << payload.merge(open_transactions: ActiveRecord::Base.connection.open_transactions)
      end
      inside = nil
      ActiveRecord::Base.transaction do
        record(@world, :used, 1, person: @world.member)
        inside = payloads.size
      end
      record(@world, :used, 1, person: @world.member)
      record(@world, :moved, 2, to_location: @world.bin2, person: @world.member)

      assert_equal 0, inside, "not published until the transaction commits"
      first, second, *move = payloads
      assert_equal %i[movement item location kind quantity person stock_after total_after went_low open_transactions].sort, first.keys.sort
      assert_equal [ @world.screws, @world.bin1, "used", -1, @world.member, 10, 10, true ],
        first.values_at(:item, :location, :kind, :quantity, :person, :stock_after, :total_after, :went_low)
      assert_equal [ 9, false ], second.values_at(:stock_after, :went_low)
      assert_equal 2, move.size
      assert_equal [ [ @world.bin1, -2, 7 ], [ @world.bin2, 2, 2 ] ], move.map { |payload| payload.values_at(:location, :quantity, :stock_after) }
      assert_equal [ 9, 9 ], move.map { |payload| payload[:total_after] }
    ensure
      ActiveSupport::Notifications.unsubscribe(subscriber)
    end
  end

  test "each sends a running low notice right away to managers within reach" do
    with_inventory(@world, inventory_reorder_notice: "each") do
      stock!(@world, 11)
      assert_enqueued_jobs(1, only: SendEmailJob) { record(@world, :used, 1) }
      assert_equal @world.keeper.user.email, enqueued_jobs.last["arguments"][1]
      assert_no_enqueued_jobs(only: SendEmailJob) { record(@world, :used, 1) }
    end
  end
end
