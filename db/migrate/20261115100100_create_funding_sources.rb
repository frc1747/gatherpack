class CreateFundingSources < ActiveRecord::Migration[8.1]
  def change
    create_table :funding_sources, id: :uuid do |t|
      t.references :team, null: false, foreign_key: true, type: :uuid
      t.string :name, null: false
      t.integer :kind, null: false, default: 0
      t.integer :amount_cents
      t.date :starts_on
      t.date :ends_on
      t.text :restriction
      t.string :giver
      t.string :reference
      t.date :report_due_on
      t.integer :spent_outside_cents, null: false, default: 0
      t.date :spent_outside_as_of
      t.references :budget, foreign_key: true, type: :uuid
      t.boolean :active, null: false, default: true

      t.timestamps
    end
  end
end
