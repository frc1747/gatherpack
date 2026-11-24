# How a person wants to hear about approved requests waiting to be bought,
# and when their daily digest last went out. No row means the defaults.
class CreateOrderNoticePreferences < ActiveRecord::Migration[8.1]
  def change
    create_table :order_notice_preferences, id: :uuid do |t|
      t.references :person, null: false, foreign_key: true, type: :uuid, index: { unique: true }
      t.integer :buyer_notices, null: false, default: 0
      t.date :digest_sent_on
      t.timestamps
    end
  end
end
