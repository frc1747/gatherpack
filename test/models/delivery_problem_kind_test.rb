require "test_helper"
require "support/orders_world"

class DeliveryProblemKindTest < ActiveSupport::TestCase
  include OrdersWorld

  setup { @world = build_orders_world }

  def ordered_line(quantity: 2)
    with_orders(@world) do
      order_request = approved_request(@world, lines: [ { description: "Gear", price: 10, quantity: quantity } ])
      buy(@world, order_request.order_lines.to_a)
      order_request.order_lines.first.reload
    end
  end

  test "a delivery with a problem kind makes the item a problem; with none it's good" do
    line = ordered_line
    with_orders(@world) do
      cracked = DeliveryProblemKind.create!(name: "Cracked")

      good = line.record_delivery!(by: @world.requester, quantity: 1)
      assert good.good?
      assert line.reload.partly_received?

      bad = line.record_delivery!(by: @world.requester, quantity: 1, problem_kind: cracked)
      assert bad.problem?
      assert line.reload.problem?
      assert_equal 1, line.problem_quantity
      assert_equal "Cracked", bad.condition_name
      assert_equal bad.delivery_problem_kind_id, line.order_request.events.where(action: "problem").last.field_changes["condition"]
    end
  end

  test "condition names a built-in kind by key" do
    line = ordered_line
    with_orders(@world) do
      delivery = line.record_delivery!(by: @world.requester, quantity: 1, condition: :wrong_item)

      assert_equal DeliveryProblemKind.find_by!(key: "wrong_item"), delivery.delivery_problem_kind
      assert_equal "wrong_item", delivery.condition
      assert line.reload.problem?
    end
  end

  test "a built-in kind looked up by key is made if it's missing" do
    DeliveryProblemKind.delete_all

    assert_equal "Damaged", DeliveryProblemKind.for_key!("damaged").name
  end

  test "renaming a kind shows the new name on old deliveries and the timeline" do
    line = ordered_line
    with_orders(@world) do
      line.record_delivery!(by: @world.requester, quantity: 1, condition: :damaged)
      DeliveryProblemKind.find_by!(key: "damaged").update!(name: "Broken")
      event = line.order_request.events.where(action: "problem").last
      helper = Object.new.extend(OrderRequestsHelper)

      assert_equal "Broken", line.order_deliveries.reload.last.condition_name
      assert_equal "Broken", helper.send(:order_timeline_condition, event.field_changes["condition"])
      assert_equal "Good", helper.send(:order_timeline_condition, "good")
    end
  end

  test "a retired kind stays on the deliveries that have it but can't be picked" do
    line = ordered_line
    with_orders(@world) do
      damaged = DeliveryProblemKind.find_by!(key: "damaged")
      delivery = line.record_delivery!(by: @world.requester, quantity: 1, problem_kind: damaged)
      damaged.retire!

      assert_equal damaged, delivery.reload.delivery_problem_kind
      assert line.reload.problem?
      assert_not_includes DeliveryProblemKind.active, damaged
      assert_not damaged.removable?
    end
  end
end
