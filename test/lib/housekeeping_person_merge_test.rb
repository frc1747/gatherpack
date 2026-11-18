require "test_helper"

# Runs only where feature/person-merge is present (an integration build).
class HousekeepingPersonMergeTest < ActiveSupport::TestCase
  setup { skip "needs feature/person-merge" unless defined?(GatherPack::PersonMerge) }

  test "covers the person columns of the housekeeping tables" do
    %w[ housekeeping_preferences housekeeping_purges ].each do |table|
      assert GatherPack::PersonMerge.covers?(table, "person_id"), "#{table}.person_id"
    end
  end

  test "saved list views keep one row per list" do
    entry = GatherPack::PersonMerge.entries.find { |e| e.table == "housekeeping_preferences" }

    assert_equal %w[ list_key ], entry.unique_by
  end
end
