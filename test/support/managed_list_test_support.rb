# A throwaway managed list for tests. Its tables are created inside each
# test's transaction, so Postgres drops them again when the test rolls back
# and nothing is added to db/schema.rb.
class ManagedListTestUnit < ApplicationRecord
  self.table_name = "managed_list_test_units"
  include ManagedList
  managed_list uses: { "ManagedListTestThing" => :unit_id }
end

class ManagedListTestThing < ApplicationRecord
  self.table_name = "managed_list_test_things"
  has_paper_trail versions: { class_name: "AuditLog" }
end

module ManagedListTestSupport
  def create_managed_list_tables
    connection = ActiveRecord::Base.connection
    connection.create_table :managed_list_test_units, id: :uuid do |t|
      t.string :name, null: false
      t.string :plural
      t.string :key
      t.integer :position, null: false, default: 0
      t.boolean :active, null: false, default: true
      t.boolean :whole_numbers, null: false, default: false
      t.timestamps
    end
    connection.create_table :managed_list_test_things, id: :uuid do |t|
      t.string :name
      t.uuid :unit_id
      t.timestamps
    end
    ManagedListTestUnit.reset_column_information
    ManagedListTestThing.reset_column_information
  end

  def register_test_list(**options)
    GatherPack::ManagedLists.register(
      :test_units,
      model: "ManagedListTestUnit",
      label: "Test Unit",
      setup_section: "Testing",
      description: "The units test things are counted in.",
      fields: [ { name: :whole_numbers, label: "Whole numbers only", hint: "Counts can't have fractions." } ],
      **options
    )
  end

  def unregister_test_list
    GatherPack::ManagedLists.unregister(:test_units)
  end
end
