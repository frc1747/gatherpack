class AddPersonFieldAndReadPermissionToCheckinFields < ActiveRecord::Migration[8.1]
  def change
    add_reference :checkin_fields, :person_field, type: :uuid, foreign_key: true
    # 7 is PersonField's "everyone" level: responses stay as visible as today.
    add_column :checkin_fields, :read_permission, :integer, default: 7, null: false
  end
end
