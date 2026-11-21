require "test_helper"
require "support/inventory_world"

class Inventory::ItemDuplicatorTest < ActiveSupport::TestCase
  include InventoryWorld

  setup do
    @world = build_inventory_world
  end

  test "copies the item's own fields, reading types and sources, and nothing else" do
    item = tracked_item!(@world, name: "Motor", units: 2, reorder_point: 3, readings: %w[Voltage Current])
    item.update!(description: "Brushless", reorder_quantity: 4, url: "https://example.com/motor", note: "Fragile")
    item.item_sources.create!(vendor_name: "Parts Depot", vendor_part_number: "PD-9", preferred: true)
    item.item_sources.create!(vendor_name: "Bin Mart", url: "https://example.com/bm")
    stock!(@world, 5, item: @world.screws)
    StockMovement.where(item: item).delete_all

    copy = nil
    assert_difference -> { Item.count } => 1, -> { ItemSource.count } => 2, -> { ItemReadingType.count } => 2 do
      copy = Inventory::ItemDuplicator.call(item)
    end

    assert copy.persisted?
    assert_equal "Motor (copy)", copy.name
    assert_equal "Motor", item.reload.name
    %i[team_id description category manufacturer manufacturer_part_number tracked home_location_id reorder_point
       reorder_quantity url note active stock_unit_id].each do |field|
      assert_equal item[field], copy[field], field.to_s unless item[field].nil?
      assert_nil copy[field], field.to_s if item[field].nil?
    end
    assert_equal item.reading_types.map(&:id), copy.reading_types.map(&:id)
    assert_equal item.item_sources.map { |s| [ s.vendor_name, s.vendor_part_number, s.url, s.preferred ] },
      copy.item_sources.map { |s| [ s.vendor_name, s.vendor_part_number, s.url, s.preferred ] }
    assert_empty copy.item_units
    assert_empty copy.stock_movements
    assert_empty copy.stock_levels
    assert_equal 2, item.item_units.count
  end

  test "does not copy stock" do
    stock!(@world, 5)
    copy = Inventory::ItemDuplicator.call(@world.screws)
    assert_equal 0, copy.total_stock
    assert_equal 5, @world.screws.total_stock
  end

  # Fails the next source save while FailingSave.on is set.
  module FailingSave
    mattr_accessor :on, default: false

    def save!(...)
      raise ActiveRecord::RecordInvalid, self if FailingSave.on

      super(...)
    end
  end
  ItemSource.prepend(FailingSave)

  test "is all or nothing" do
    @world.screws.item_sources.create!(vendor_name: "Parts Depot")
    FailingSave.on = true
    assert_no_difference -> { Item.count } do
      assert_raises(ActiveRecord::RecordInvalid) { Inventory::ItemDuplicator.call(@world.screws) }
    end
  ensure
    FailingSave.on = false
  end
end
