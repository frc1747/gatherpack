# Who made a grant, so an item kind can check that its maker could give the
# access it grants (ItemKind.honours_grant?).
class AddCreatedByToChecklistGrants < ActiveRecord::Migration[8.1]
  def change
    add_reference :checklist_grants, :created_by, foreign_key: { to_table: :people, on_delete: :nullify }, type: :uuid
  end
end
