class AddGroupsAndExemptBadgeToCommitments < ActiveRecord::Migration[8.1]
  def change
    add_reference :commitments, :exempt_badge, type: :uuid, foreign_key: { to_table: :badges }
    add_reference :commitments, :group_relationship_type, type: :uuid, foreign_key: { to_table: :relationship_types }
    add_column :commitments, :additional_amount, :integer, null: false, default: 0
  end
end
