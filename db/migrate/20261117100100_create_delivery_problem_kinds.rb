# What can be wrong with a delivery becomes a managed list. A delivery is
# good (no kind) or has a problem kind; the condition enum (1 damaged,
# 2 wrong item) turns into the keyed default rows.
class CreateDeliveryProblemKinds < ActiveRecord::Migration[8.1]
  CONDITIONS = { 1 => "damaged", 2 => "wrong_item" }.freeze

  def up
    create_table :delivery_problem_kinds, id: :uuid do |t|
      t.string :name, null: false
      t.string :plural
      t.string :key
      t.integer :position, null: false, default: 0
      t.boolean :active, null: false, default: true
      t.timestamps
    end
    add_index :delivery_problem_kinds, "lower(name)", unique: true
    add_index :delivery_problem_kinds, :key, unique: true
    add_reference :order_deliveries, :delivery_problem_kind, type: :uuid, foreign_key: true

    DeliveryProblemKind.reset_column_information
    Orders::Lists.seed_delivery_problem_kinds!
    CONDITIONS.each do |condition, key|
      execute <<~SQL.squish
        UPDATE order_deliveries SET delivery_problem_kind_id = (SELECT id FROM delivery_problem_kinds WHERE key = #{quote(key)})
        WHERE condition = #{condition}
      SQL
    end
    remove_column :order_deliveries, :condition
  end

  # Kinds added since come back as damaged: still a problem, as they were.
  def down
    add_column :order_deliveries, :condition, :integer, null: false, default: 0
    execute <<~SQL.squish
      UPDATE order_deliveries SET condition = CASE delivery_problem_kinds.key WHEN 'wrong_item' THEN 2 ELSE 1 END
      FROM delivery_problem_kinds WHERE delivery_problem_kinds.id = order_deliveries.delivery_problem_kind_id
    SQL
    remove_reference :order_deliveries, :delivery_problem_kind, foreign_key: true
    drop_table :delivery_problem_kinds
  end

  private

  def quote(value)
    connection.quote(value)
  end
end
