class AddChecklistToFormAudienceRules < ActiveRecord::Migration[8.1]
  def change
    # A rule can ask the people a checklist covers, or those of them who have
    # or haven't finished it. Deleting a checklist a rule uses is refused.
    add_reference :form_audience_rules, :checklist, type: :uuid, foreign_key: true
    add_column :form_audience_rules, :checklist_match, :integer, null: false, default: 0

    remove_index :form_audience_rules, [ :form_id, :effect, :target_type, :team_id, :badge_id, :person_id ], unique: true,
      nulls_not_distinct: true, name: "index_form_audience_rules_uniqueness"
    add_index :form_audience_rules, [ :form_id, :effect, :target_type, :team_id, :badge_id, :person_id, :checklist_id, :checklist_match ],
      unique: true, nulls_not_distinct: true, name: "index_form_audience_rules_uniqueness"
  end
end
