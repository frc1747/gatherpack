require "test_helper"

# Runs only where feature/person-merge is present (an integration build).
class CommitmentsPersonMergeTest < ActiveSupport::TestCase
  setup { skip "needs feature/person-merge" unless defined?(GatherPack::PersonMerge) }

  test "covers the person columns of the commitment tables" do
    { commitments: %w[ created_by_id ], commitment_organizers: %w[ person_id ],
      commitment_adjustments: %w[ person_id created_by_id ] }.each do |table, columns|
      columns.each { |column| assert GatherPack::PersonMerge.covers?(table, column), "#{table}.#{column}" }
    end
  end

  test "credit sources follow a person and a login" do
    %i[ person user ].each do |owner|
      assert GatherPack::PersonMerge.covers?(:commitment_sources, :subject_id, owner: owner), "commitment_sources.subject_id (#{owner})"
    end
  end

  test "organizers keep one row per commitment" do
    entry = GatherPack::PersonMerge.entries.find { |e| e.table == "commitment_organizers" }

    assert_equal %w[ commitment_id ], entry.unique_by
  end
end
