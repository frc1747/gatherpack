class AddShowContactDetailsToRelationshipTypes < ActiveRecord::Migration[8.1]
  def change
    add_column :relationship_types, :show_contact_details, :boolean, default: false, null: false
  end
end
