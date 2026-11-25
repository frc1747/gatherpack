class CreateOrderApprovals < ActiveRecord::Migration[8.1]
  def change
    create_table :order_approvals, id: :uuid do |t|
      t.references :order_request, null: false, foreign_key: true, type: :uuid
      t.string :step_key, null: false
      t.references :approver, null: false, foreign_key: { to_table: :people }, type: :uuid
      t.integer :decision, null: false
      t.text :comment
      t.datetime :cleared_at

      t.timestamps
    end
  end
end
