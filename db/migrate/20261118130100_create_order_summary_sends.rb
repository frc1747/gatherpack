# When Orders' own summary email last went to each person, so a second run
# the same day sends nothing (Orders::Reminders.digest).
class CreateOrderSummarySends < ActiveRecord::Migration[8.1]
  def change
    create_table :order_summary_sends, id: :uuid do |t|
      t.references :person, null: false, foreign_key: { on_delete: :cascade }, type: :uuid, index: { unique: true }
      t.date :sent_on, null: false
      t.timestamps
    end
  end
end
