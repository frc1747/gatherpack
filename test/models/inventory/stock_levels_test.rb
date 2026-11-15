require "test_helper"
require "support/inventory_world"
require "rake"

class Inventory::StockLevelsTest < ActiveSupport::TestCase
  include InventoryWorld

  setup { @world = build_inventory_world }

  test "the rebuild finds and fixes a tampered level" do
    with_inventory(@world) do
      stock!(@world, 9)
      record(@world, :used, 2)
      level = StockLevel.find_by(item: @world.screws, location: @world.bin1)
      level.update_columns(quantity: 40)

      differences = Inventory::StockLevels.rebuild!(fix: true)

      assert_equal 1, differences.size
      assert_equal [ 40, 7 ], [ differences.first.cached, differences.first.actual ]
      assert_equal 7, level.reload.quantity
      assert_empty Inventory::StockLevels.rebuild!(fix: true)
    end
  end

  test "a missing level is created, and without fix nothing changes" do
    with_inventory(@world) do
      stock!(@world, 3)
      StockLevel.where(item: @world.screws).delete_all

      assert_equal 1, Inventory::StockLevels.rebuild!(fix: false).size
      assert_not StockLevel.exists?(item: @world.screws)

      Inventory::StockLevels.rebuild!
      assert_equal 3, StockLevel.find_by(item: @world.screws, location: @world.bin1).quantity
    end
  end

  test "the rake task reports and fixes" do
    with_inventory(@world) do
      stock!(@world, 3)
      StockLevel.find_by(item: @world.screws).update_columns(quantity: 1)
      Rails.application.load_tasks unless Rake::Task.task_defined?("inventory:rebuild_stock_levels")

      output = capture_io { Rake::Task["inventory:rebuild_stock_levels"].execute }.first

      assert_match "M4 screw at Shop › Cabinet › Bin 1: was 1, now 3", output
      assert_equal 3, StockLevel.find_by(item: @world.screws).quantity
    end
  end
end
