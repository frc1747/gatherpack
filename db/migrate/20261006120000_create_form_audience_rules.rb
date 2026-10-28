class CreateFormAudienceRules < ActiveRecord::Migration[8.1]
  def change
    create_table :form_audience_rules, id: :uuid do |t|
      t.references :form, type: :uuid, null: false, foreign_key: { on_delete: :cascade }
      t.integer :effect, null: false, default: 0
      t.integer :target_type, null: false, default: 0
      t.references :team, type: :uuid, foreign_key: { on_delete: :cascade }
      t.references :badge, type: :uuid, foreign_key: { on_delete: :cascade }
      t.references :person, type: :uuid, foreign_key: { on_delete: :cascade }
      t.boolean :include_managers, null: false, default: true

      t.timestamps
    end
    add_index :form_audience_rules, [ :form_id, :effect, :target_type, :team_id, :badge_id, :person_id ], unique: true,
      nulls_not_distinct: true, name: "index_form_audience_rules_uniqueness"

    # Every existing form keeps the audience it had: its team and everything
    # below it, managers included.
    reversible do |dir|
      dir.up do
        execute <<~SQL
          INSERT INTO form_audience_rules (form_id, effect, target_type, team_id, include_managers, created_at, updated_at)
          SELECT id, 0, 0, team_id, TRUE, NOW(), NOW() FROM forms
        SQL
      end
    end
  end
end
