require "test_helper"
require "support/orders_world"
require Rails.root.join("db/migrate/20261118130000_copy_order_notice_choices")

# Retiring the Buying notices page copies each buyer's choice into
# Summaries' notice_preferences, where that table exists.
class Orders::CopyOrderNoticeChoicesTest < ActiveSupport::TestCase
  include OrdersWorld

  setup { @world = build_orders_world }

  def connection
    ActiveRecord::Base.connection
  end

  def migrate(direction)
    ActiveRecord::Migration.suppress_messages { CopyOrderNoticeChoices.new.migrate(direction) }
  end

  # The table as Summaries makes it, made here (inside the test's
  # transaction) where that seam isn't merged.
  def with_notice_preferences
    unless connection.table_exists?(:notice_preferences)
      connection.create_table :notice_preferences, id: :uuid do |t|
        t.references :person, null: false, type: :uuid
        t.string :key, null: false
        t.string :delivery, null: false
        t.timestamps
        t.index %i[person_id key], unique: true
      end
    end
    yield
  end

  def choices
    connection.select_rows("SELECT person_id, key, delivery FROM notice_preferences WHERE key = 'orders'")
      .to_h { |person_id, _key, delivery| [ person_id, delivery ] }
  end

  test "digest becomes daily, immediate each and off off, a choice already made stands, and down takes the copies back" do
    with_notice_preferences do
      OrderNoticePreference.create!(person: @world.buyer, buyer_notices: :digest)
      OrderNoticePreference.create!(person: @world.manager, buyer_notices: :immediate)
      OrderNoticePreference.create!(person: @world.admin, buyer_notices: :off)
      OrderNoticePreference.create!(person: @world.mentor, buyer_notices: :immediate)
      connection.execute("INSERT INTO notice_preferences (person_id, key, delivery, created_at, updated_at) " \
        "VALUES ('#{@world.mentor.id}', 'orders', 'weekly', NOW(), NOW())")

      migrate(:up)

      assert_equal({ @world.buyer.id => "daily", @world.manager.id => "each", @world.admin.id => "off", @world.mentor.id => "weekly" }, choices)

      migrate(:down)

      assert_equal({ @world.mentor.id => "weekly" }, choices)
      assert_equal 4, OrderNoticePreference.count, "the old rows stay"
    end
  end

  test "without Summaries' table there's nothing to copy into" do
    skip "notice_preferences is here" if connection.table_exists?(:notice_preferences)

    OrderNoticePreference.create!(person: @world.buyer, buyer_notices: :immediate)
    assert_nothing_raised { migrate(:up) }
    assert_nothing_raised { migrate(:down) }
  end
end
