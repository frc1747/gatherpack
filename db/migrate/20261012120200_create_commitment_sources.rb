class CreateCommitmentSources < ActiveRecord::Migration[8.1]
  def change
    create_table :commitment_sources, id: :uuid do |t|
      t.references :commitment, type: :uuid, null: false, foreign_key: { on_delete: :cascade }
      t.string :kind, null: false
      t.references :subject, type: :uuid, polymorphic: true
      t.integer :per, null: false, default: 1
      t.integer :credits, null: false, default: 1
      t.integer :max_credits
      t.integer :position, null: false, default: 0

      t.timestamps
    end
  end
end
