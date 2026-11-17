# Deleting a person named in a rule used to delete the rule too, which could
# widen who a checklist covers. The rule now stays with no person, matches
# nobody, and shows as a setup problem.
class KeepChecklistRulesWhenTheirPersonIsDeleted < ActiveRecord::Migration[8.1]
  def up
    remove_foreign_key :checklist_rules, :people
    add_foreign_key :checklist_rules, :people, on_delete: :nullify
  end

  def down
    remove_foreign_key :checklist_rules, :people
    add_foreign_key :checklist_rules, :people, on_delete: :cascade
  end
end
