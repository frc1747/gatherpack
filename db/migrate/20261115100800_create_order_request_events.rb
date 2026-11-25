# The request timeline. Rows are only ever inserted: the model refuses
# updates and deletes, so there is no updated_at.
class CreateOrderRequestEvents < ActiveRecord::Migration[8.1]
  def change
    create_table :order_request_events, id: :uuid do |t|
      t.references :order_request, null: false, foreign_key: true, type: :uuid
      t.references :order_line, foreign_key: true, type: :uuid
      t.references :actor, foreign_key: { to_table: :people }, type: :uuid
      t.string :action, null: false
      t.string :step_key
      t.jsonb :field_changes, null: false, default: {}
      t.text :comment
      t.datetime :created_at, null: false
    end
    add_index :order_request_events, %i[order_request_id created_at]
  end
end
