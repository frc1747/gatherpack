require "test_helper"
require "support/orders_world"

class OrderRequestEventTest < ActiveSupport::TestCase
  include OrdersWorld

  setup { @world = build_orders_world }

  test "timeline entries can't be edited or deleted" do
    with_orders(@world) do
      event = submitted_request(@world).events.first

      assert_raises(ActiveRecord::ReadOnlyRecord) { event.update!(comment: "changed") }
      assert_raises(ActiveRecord::ReadOnlyRecord) { event.destroy }
      assert_raises(ActiveRecord::ReadOnlyRecord) { event.delete }
      assert_equal "submitted", OrderRequestEvent.find(event.id).action
    end
  end

  test "every change writes a timeline entry" do
    with_orders(@world) do
      order_request = submitted_request(@world, lines: [ { description: "A", price: 5, quantity: 2 } ])
      order_request.comment!("Is blue OK?", by: @world.mentor)
      order_request.decide!(:approved, by: @world.mentor)
      line = order_request.reload.order_lines.first
      buy(@world, [ line ])
      line.reload.backorder!(by: @world.buyer, expected_on: Date.current + 7)
      line.reload.record_delivery!(by: @world.requester, quantity: 1)
      line.reload.record_delivery!(by: @world.requester, quantity: 1)
      order_request.reload.close!(by: @world.requester)

      assert_equal %w[submitted commented approved purchased backordered received received closed],
        order_request.reload.events.map(&:action)
    end
  end

  test "an action that fails writes nothing" do
    with_orders(@world) do
      order_request = submitted_request(@world)

      assert_no_difference -> { OrderRequestEvent.count } do
        assert_raises(Orders::Refused) { order_request.decide!(:approved, by: @world.requester) }
      end
    end
  end
end
