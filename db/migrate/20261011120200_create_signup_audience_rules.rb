class CreateSignupAudienceRules < ActiveRecord::Migration[8.1]
  def change
    create_table :signup_audience_rules, id: :uuid do |t|
      t.references :signup_sheet, type: :uuid, null: false, foreign_key: { on_delete: :cascade }
      t.integer :effect, null: false, default: 0
      t.integer :target_type, null: false, default: 0
      t.references :team, type: :uuid, foreign_key: { on_delete: :cascade }
      t.references :badge, type: :uuid, foreign_key: { on_delete: :cascade }
      t.references :person, type: :uuid, foreign_key: { on_delete: :cascade }
      t.boolean :include_managers, null: false, default: true

      t.timestamps
    end
    add_index :signup_audience_rules, [ :signup_sheet_id, :effect, :target_type, :team_id, :badge_id, :person_id ], unique: true,
      nulls_not_distinct: true, name: "index_signup_audience_rules_uniqueness"
  end
end
