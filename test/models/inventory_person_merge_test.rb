require "test_helper"

# The initializer registers where people can be merged
# (GatherPack::PersonMerge is loaded) and does nothing elsewhere.
class InventoryPersonMergeTest < ActiveSupport::TestCase
  COLUMNS = %w[
    stock_movements.person_id stock_movements.recorded_by_id
    item_unit_events.person_id item_unit_events.recorded_by_id
  ].freeze

  test "preparing without a person merge registry does nothing" do
    skip "people can be merged here" if defined?(GatherPack::PersonMerge)

    assert_nothing_raised { Rails.application.reloader.prepare! }
  end

  test "every column inventory adds is covered by a merge" do
    skip "people can't be merged here" unless defined?(GatherPack::PersonMerge)

    uncovered = COLUMNS.reject { |name| GatherPack::PersonMerge.covers?(*name.split(".")) }

    assert_empty uncovered
  end

  test "every registered inventory column exists" do
    skip "people can't be merged here" unless defined?(GatherPack::PersonMerge)

    COLUMNS.each do |name|
      table, column = name.split(".")
      assert ActiveRecord::Base.connection.column_exists?(table, column), name
    end
  end
end
