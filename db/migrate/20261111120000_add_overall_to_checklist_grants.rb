# Whether a grant shows the checklist's overall, like the items it lists.
# Existing grants keep showing it.
class AddOverallToChecklistGrants < ActiveRecord::Migration[8.1]
  def change
    add_column :checklist_grants, :overall, :boolean, default: true, null: false
  end
end
