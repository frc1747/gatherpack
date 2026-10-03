class AddGuardianshipToRelationshipTypes < ActiveRecord::Migration[8.1]
  def change
    add_column :relationship_types, :guardianship, :integer, default: 0, null: false
  end
end
