# What a checklist's reminders may say about its items: "everything",
# "name_only" or "sign_in" (Checklists::EmailLevel). The most any of its items
# may say.
class AddEmailLevelToChecklists < ActiveRecord::Migration[8.1]
  def change
    add_column :checklists, :email_level, :string, default: "everything", null: false
  end
end
