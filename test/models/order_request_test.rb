require "test_helper"
require "support/orders_world"

class OrderRequestTest < ActiveSupport::TestCase
  include OrdersWorld

  setup { @world = build_orders_world }

  test "draft_for makes a draft with its lines and writes no timeline" do
    with_orders(@world) do
      order_request = draft_request(@world, lines: [ { description: "Gear", price: 10 }, { url: "https://partsdepot.example/p/X1" } ])

      assert order_request.draft?
      assert_equal 2, order_request.order_lines.count
      assert order_request.order_lines.all?(&:pending?)
      assert_empty order_request.events
    end
  end

  test "a line with only a link submits, and so does one with only a description" do
    with_orders(@world) do
      assert submitted_request(@world, lines: [ { url: "https://partsdepot.example/p/X1" } ]).submitted?
      assert submitted_request(@world, lines: [ { description: "Zip ties" } ]).submitted?
    end
  end

  test "a line with neither a link nor a description is refused" do
    with_orders(@world) do
      assert_raises(ActiveRecord::RecordInvalid) { draft_request(@world, lines: [ { quantity: 2 } ]) }
    end
  end

  test "an other store line needs a reason only when the setting says so" do
    with_orders(@world) do
      assert draft_request(@world, lines: [ { description: "Glue", other_vendor_name: "Corner Store" } ]).persisted?
    end
    with_orders(@world, orders_require_other_vendor_reason: "true") do
      assert_raises(ActiveRecord::RecordInvalid) { draft_request(@world, lines: [ { description: "Glue", other_vendor_name: "Corner Store" } ]) }
      assert draft_request(@world, lines: [ { description: "Glue", other_vendor_name: "Corner Store", other_vendor_reason: "Open late" } ]).persisted?
    end
  end

  test "submitting takes a blank title from the first line and writes the timeline" do
    with_orders(@world) do
      order_request = submitted_request(@world, lines: [ { description: "Drive motor", price: 30 }, { description: "Wheel" } ])

      assert_equal "Drive motor", order_request.title
      assert_not_nil order_request.submitted_at
      assert_equal [ "submitted" ], order_request.events.map(&:action)
      assert_equal @world.requester, order_request.events.first.actor
    end
  end

  test "submitting twice, or with no items, is refused" do
    with_orders(@world) do
      order_request = submitted_request(@world)
      assert_raises(Orders::Refused) { order_request.submit!(by: @world.requester) }

      empty = OrderRequest.create!(team: @world.robotics, requested_by: @world.requester)
      assert_raises(Orders::Refused) { empty.submit!(by: @world.requester) }
    end
  end

  test "the total is the lines' quantity times price, actual where known, plus estimated shipping" do
    with_orders(@world) do
      order_request = draft_request(@world, lines: [ { description: "A", price: 10, quantity: 3 }, { description: "B" } ],
        estimated_shipping_cents: 500)
      order_request.order_lines.first.update!(actual_unit_price_cents: 1200)

      assert_equal 3 * 1200 + 500, order_request.reload.total_cents
    end
  end

  test "a draft can be cancelled or deleted; a submitted one cancelled but not deleted" do
    with_orders(@world) do
      draft = draft_request(@world)
      draft.destroy!
      assert_not OrderRequest.exists?(draft.id)

      order_request = submitted_request(@world)
      order_request.cancel!(by: @world.requester, reason: "Found one")
      assert order_request.reload.cancelled?
      assert order_request.order_lines.all?(&:cancelled?)
      assert_equal "cancelled", order_request.events.last.action
      assert_not order_request.destroy
      assert OrderRequest.exists?(order_request.id)
    end
  end

  test "cancelling is refused once anything is ordered" do
    with_orders(@world) do
      order_request = approved_request(@world, lines: [ { description: "A", price: 5 }, { description: "B", price: 5 } ])
      buy(@world, [ order_request.order_lines.first ])

      assert_raises(Orders::Refused) { order_request.reload.cancel!(by: @world.requester) }
    end
  end

  test "ordering and received follow the lines" do
    with_orders(@world) do
      order_request = approved_request(@world, lines: [ { description: "A", price: 5 }, { description: "B", price: 5 } ])
      first, second = order_request.order_lines.to_a
      assert order_request.approved?

      buy(@world, [ first ])
      assert order_request.reload.ordering?

      first.reload.record_delivery!(by: @world.requester, quantity: 1)
      assert order_request.reload.ordering?

      second.reload.cancel!(by: @world.buyer, reason: "Out of stock everywhere")
      assert order_request.reload.received?
    end
  end

  test "close works only once received, and is in the timeline" do
    with_orders(@world) do
      order_request = approved_request(@world)
      assert_raises(Orders::Refused) { order_request.close!(by: @world.requester) }

      buy(@world, order_request.order_lines.to_a)
      order_request.reload.mark_all_received!(by: @world.requester)
      order_request.reload.close!(by: nil)

      assert order_request.reload.closed?
      assert_not_nil order_request.closed_at
      assert_equal "closed", order_request.events.last.action
    end
  end

  test "duplicate copies the lines into a new draft at their last price, titled as a copy" do
    with_orders(@world) do
      order_request = approved_request(@world, lines: [ { description: "Gear", price: 10, quantity: 4 } ])
      buy(@world, order_request.order_lines.to_a, prices: { order_request.order_lines.first.id => 1250 })

      copy = order_request.reload.order_again(by: @world.teammate)

      assert copy.draft?
      assert_equal "#{order_request.display_title} (copy)", copy.title
      assert_equal @world.teammate, copy.requested_by
      line = copy.order_lines.first
      assert_equal [ "Gear", 4, 1250 ], [ line.description, line.quantity, line.estimated_unit_price_cents ]
      assert line.pending?
    end
  end

  test "once approved, estimated shipping and the team are fixed and approvals stand" do
    with_orders(@world) do
      order_request = approved_request(@world)

      assert_raises(Orders::Refused) { order_request.edit!({ estimated_shipping_cents: 50_000 }, by: @world.manager) }
      order_request.reload.edit!({ purpose: "For the spring build" }, by: @world.manager)
      order_request.reload

      assert order_request.approved?
      assert_equal 0, order_request.estimated_shipping_cents
      assert_equal 1, order_request.active_approvals.size
      assert_not order_request.events.last.field_changes.key?("approvals_cleared")
    end
  end

  test "a requester can't set the funding source or estimated shipping unless allowed" do
    with_orders(@world) do
      source = FundingSource.create!(team: @world.robotics, name: "Build budget")
      order_request = submitted_request(@world)

      assert_raises(Orders::Refused) { order_request.edit!({ funding_source_id: source.id }, by: @world.requester) }
      assert_raises(Orders::Refused) { order_request.reload.edit!({ estimated_shipping_cents: 0 + 900 }, by: @world.requester) }
      assert_nil order_request.reload.funding_source_id

      order_request.edit!({ funding_source_id: source.id, estimated_shipping_cents: 900 }, by: @world.mentor)
      assert_equal [ source.id, 900 ], order_request.reload.values_at(:funding_source_id, :estimated_shipping_cents)
    end
    with_orders(@world, orders_requesters_pick_funding: "true") do
      source = FundingSource.create!(team: @world.robotics, name: "Other budget")
      order_request = submitted_request(@world)
      order_request.edit!({ funding_source_id: source.id }, by: @world.requester)

      assert_equal source.id, order_request.reload.funding_source_id
    end
  end

  test "following and unfollowing" do
    with_orders(@world) do
      order_request = submitted_request(@world)
      order_request.follow!(@world.teammate)
      order_request.follow!(@world.teammate)

      assert_equal [ @world.teammate ], order_request.reload.watchers.to_a
      assert_equal "followed", order_request.events.last.action

      order_request.unfollow!(@world.teammate)
      assert_empty order_request.reload.watchers
    end
  end

  test "a status change sends order_request_changed with from and to" do
    with_orders(@world) do
      order_request = draft_request(@world)
      received = []
      callback = ->(*, payload) { received << payload.values_at(:order_request, :from, :to) }
      ActiveSupport::Notifications.subscribed(callback, "order_request_changed.gatherpack") do
        order_request.submit!(by: @world.requester)
      end

      assert_equal [ [ order_request, "draft", "submitted" ] ], received
    end
  end

  test "status hooks fire for submitted, final approval and declined" do
    with_orders(@world) do
      fired = []
      original = Orders.method(:run_hooks)
      Orders.define_singleton_method(:run_hooks) { |event, record| fired << event }
      begin
        order_request = approved_request(@world)
        declined = submitted_request(@world)
        declined.decide!(:declined, by: @world.mentor, comment: "Not this season")
      ensure
        Orders.define_singleton_method(:run_hooks, original)
      end

      assert_equal [ "order_requests - submitted", "order_requests - approved", "order_requests - submitted", "order_requests - declined" ], fired
      assert order_request.approved?
    end
  end

  test "hook catalog lists the orders targets and events" do
    catalog = Hook.catalog

    assert_includes catalog, "order_requests - create"
    assert_includes catalog, "order_lines - received"
    assert_includes catalog, "order_requests - approved"
    assert_not_includes catalog, "order_request_events - create"
  end
end
