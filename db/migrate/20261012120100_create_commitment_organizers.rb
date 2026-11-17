class CreateCommitmentOrganizers < ActiveRecord::Migration[8.1]
  def change
    create_table :commitment_organizers, id: :uuid do |t|
      t.references :commitment, type: :uuid, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.references :person, type: :uuid, null: false, foreign_key: { on_delete: :cascade }

      t.timestamps
    end
    add_index :commitment_organizers, [ :commitment_id, :person_id ], unique: true
  end
end
