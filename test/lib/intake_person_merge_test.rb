require "test_helper"

# Runs only where feature/person-merge is present (an integration build).
class IntakePersonMergeTest < ActiveSupport::TestCase
  setup { skip "needs feature/person-merge" unless defined?(GatherPack::PersonMerge) }

  test "covers the person columns of the intake tables" do
    { intake_entries: "person_id", intake_household_members: "person_id", intake_registrations: "created_by_id" }.each do |table, column|
      assert GatherPack::PersonMerge.covers?(table, column), "#{table}.#{column}"
    end
  end
end
