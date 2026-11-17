class AddIntakeColumnsToApplicationsAndUsers < ActiveRecord::Migration[8.1]
  def change
    add_reference :membership_applications, :registration, type: :uuid, foreign_key: { to_table: :intake_registrations, on_delete: :nullify }
    add_column :membership_applications, :source, :integer, default: 0, null: false
    add_column :users, :intake_login_verified_at, :datetime
  end
end
