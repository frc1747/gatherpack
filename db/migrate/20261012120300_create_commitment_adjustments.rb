class CreateCommitmentAdjustments < ActiveRecord::Migration[8.1]
  def change
    create_table :commitment_adjustments, id: :uuid do |t|
      t.references :commitment, type: :uuid, null: false, foreign_key: { on_delete: :cascade }
      t.references :person, type: :uuid, null: false, foreign_key: { on_delete: :cascade }
      t.integer :credits, null: false
      t.text :reason, null: false
      t.references :created_by, type: :uuid, foreign_key: { to_table: :people, on_delete: :nullify }

      t.timestamps
    end
  end
end
