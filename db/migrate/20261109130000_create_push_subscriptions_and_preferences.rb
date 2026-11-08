class CreatePushSubscriptionsAndPreferences < ActiveRecord::Migration[8.1]
  def change
    create_table :push_subscriptions, id: :uuid do |t|
      t.references :user, type: :uuid, null: false, foreign_key: { on_delete: :cascade }
      t.text :endpoint, null: false, index: { unique: true }
      t.string :p256dh, null: false
      t.string :auth, null: false
      t.string :device_label
      t.datetime :last_sent_at

      t.timestamps
    end

    create_table :push_preferences, id: :uuid do |t|
      t.references :user, type: :uuid, null: false, foreign_key: { on_delete: :cascade }, index: { unique: true }
      t.string :enabled_topics, array: true, null: false, default: []

      t.timestamps
    end
  end
end
