# Remembers that a once-only reminder went out for a request, so the daily
# jobs don't repeat it. detail names the occasion (the date it was needed,
# the submission it was waiting on), so a new one can be reminded again.
class CreateOrderNoticeMarks < ActiveRecord::Migration[8.1]
  def change
    create_table :order_notice_marks, id: :uuid do |t|
      t.references :order_request, null: false, foreign_key: true, type: :uuid
      t.string :kind, null: false
      t.string :detail
      t.datetime :sent_at, null: false
      t.timestamps
    end
    add_index :order_notice_marks, %i[order_request_id kind], unique: true
  end
end
