# The Buying notices page is retired: each buyer's choice there becomes their
# Orders choice in Summaries' notice_preferences (digest → daily, immediate
# → each, off → off), where that table exists. A choice already made there
# stands. order_notice_preferences stays, unread, to be dropped later.
class CopyOrderNoticeChoices < ActiveRecord::Migration[8.1]
  # order_notice_preferences.buyer_notices: digest 0, immediate 1, off 2.
  MAPPING = "CASE buyer_notices WHEN 0 THEN 'daily' WHEN 1 THEN 'each' WHEN 2 THEN 'off' END".freeze

  def up
    return unless table_exists?(:notice_preferences)

    execute <<~SQL.squish
      INSERT INTO notice_preferences (person_id, key, delivery, created_at, updated_at)
      SELECT person_id, 'orders', #{MAPPING}, NOW(), NOW()
      FROM order_notice_preferences
      WHERE buyer_notices IN (0, 1, 2)
      ON CONFLICT (person_id, key) DO NOTHING
    SQL
  end

  # Removes the orders choices that still say what the old rows said.
  def down
    return unless table_exists?(:notice_preferences)

    execute <<~SQL.squish
      DELETE FROM notice_preferences
      USING order_notice_preferences
      WHERE notice_preferences.person_id = order_notice_preferences.person_id
        AND notice_preferences.key = 'orders'
        AND notice_preferences.delivery = #{MAPPING}
    SQL
  end
end
