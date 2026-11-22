class CreateOrderRequestWatchers < ActiveRecord::Migration[8.1]
  def change
    create_table :order_request_watchers, id: :uuid do |t|
      t.references :order_request, null: false, foreign_key: true, type: :uuid
      t.references :person, null: false, foreign_key: true, type: :uuid

      t.timestamps
    end
    add_index :order_request_watchers, %i[order_request_id person_id], unique: true
  end
end
