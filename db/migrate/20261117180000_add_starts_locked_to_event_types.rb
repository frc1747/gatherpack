class AddStartsLockedToEventTypes < ActiveRecord::Migration[8.1]
  def change
    add_column :event_types, :starts_locked, :boolean, default: false, null: false
  end
end
