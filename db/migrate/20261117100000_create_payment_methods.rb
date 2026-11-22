# Payment methods become a managed list (rule: things a group names are
# rows). The rows come from the defaults, the old orders_paid_with setting
# and every distinct text a purchase was paid with; each purchase then
# points at its row and the text column and the setting go.
class CreatePaymentMethods < ActiveRecord::Migration[8.1]
  def up
    create_table :payment_methods, id: :uuid do |t|
      t.string :name, null: false
      t.string :plural
      t.string :key
      t.integer :position, null: false, default: 0
      t.boolean :active, null: false, default: true
      t.boolean :reimburse, null: false, default: false
      t.timestamps
    end
    add_index :payment_methods, "lower(name)", unique: true
    add_index :payment_methods, :key, unique: true
    add_reference :purchases, :payment_method, type: :uuid, foreign_key: true

    PaymentMethod.reset_column_information
    Purchase.reset_column_information
    Orders::Lists.convert_payment_methods!(Orders::Lists.stored_setting(:orders_paid_with))
    remove_column :purchases, :paid_with
    Purchase.reset_column_information
    Orders::Lists.forget_setting(:orders_paid_with)
  end

  def down
    add_column :purchases, :paid_with, :string
    execute <<~SQL.squish
      UPDATE purchases SET paid_with = payment_methods.name
      FROM payment_methods WHERE payment_methods.id = purchases.payment_method_id
    SQL
    Orders::Lists.restore_setting(:orders_paid_with, Orders::Lists.payment_methods_json)
    remove_reference :purchases, :payment_method, foreign_key: true
    drop_table :payment_methods
    Purchase.reset_column_information
  end
end
