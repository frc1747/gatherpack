# An item's own email level, which can only lower the checklist's. Null means
# the same as the checklist.
class AddEmailLevelToChecklistItems < ActiveRecord::Migration[8.1]
  def change
    add_column :checklist_items, :email_level, :string
  end
end
