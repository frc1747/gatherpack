require "test_helper"
require_relative "../support/person_fields_world"

# Runs only where feature/person-merge is present (an integration build).
class PersonFieldsPersonMergeTest < ActiveSupport::TestCase
  include PersonFieldsWorld

  setup do
    skip "needs feature/person-merge" unless defined?(GatherPack::PersonMerge)
    build_person_fields_world
  end

  test "covers the person columns of person field values" do
    %w[ person_id updated_by_id ].each do |column|
      assert GatherPack::PersonMerge.covers?(:person_field_values, column), "person_field_values.#{column}"
    end
  end

  test "a blank kept answer is filled by the removed one, and a given one stays" do
    field = create_world_field("Food Allergies", read: "family", write: "family")
    kept = PersonFieldValue.create!(person: person(:a1), person_field: field, value: "")
    removed = PersonFieldValue.create!(person: person(:a2), person_field: field, value: "peanuts")
    conflict = GatherPack::PersonMerge.entries.find { |e| e.table == "person_field_values" && e.column == "person_id" }.on_conflict

    conflict.call(removed.attributes, kept.attributes)
    assert_equal "peanuts", kept.reload.value

    removed.update_columns(value: "shellfish")
    conflict.call(removed.attributes, kept.reload.attributes)
    assert_equal "peanuts", kept.reload.value
  end
end
