class CreateSignupPositionRules < ActiveRecord::Migration[8.1]
  def change
    create_table :signup_position_rules, id: :uuid do |t|
      t.references :signup_position, type: :uuid, null: false, foreign_key: { on_delete: :cascade }
      t.integer :kind, null: false, default: 0
      t.uuid :badge_ids, array: true, null: false, default: []
      t.integer :min_age
      t.integer :max_age
      t.references :team, type: :uuid, foreign_key: { on_delete: :cascade }

      t.timestamps
    end
  end
end
