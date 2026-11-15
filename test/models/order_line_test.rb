require "test_helper"
require "support/orders_world"

class OrderLineTest < ActiveSupport::TestCase
  include OrdersWorld

  setup { @world = build_orders_world }

  def ordered_line(quantity: 4, price: 10)
    order_request = approved_request(@world, lines: [ { description: "Bolt pack", price: price, quantity: quantity } ])
    buy(@world, order_request.order_lines.to_a)
    order_request.order_lines.first.reload
  end

  test "a line's link must be an http or https web page" do
    order_request = draft_request(@world)
    line = order_request.order_lines.sole

    [ "javascript:alert(1)", "data:text/html,hi", "ftp://shop.example/x", "https://" ].each do |url|
      line.url = url
      assert_not line.valid?, "#{url} should be refused"
      assert_includes line.errors[:base], "The link must be a web page (http:// or https://)"
    end
    line.url = "HTTPS://shop.example/p/1"
    assert line.valid?
  end

  test "drafts are deleted through discard_draft!, and nothing else is" do
    draft = draft_request(@world)
    draft.discard_draft!(by: @world.requester)
    assert_not OrderRequest.exists?(draft.id)

    submitted = submitted_request(@world)
    assert_raises(Orders::Refused) { submitted.discard_draft!(by: @world.requester) }
    assert_raises(Orders::Refused) { draft_request(@world).comment!("Hello", by: @world.requester) }
  end

  test "a line's vendor is a vendor, another store, or not sure" do
    line = OrderLine.new(vendor: @world.preferred_vendor, other_vendor_name: "ignored")
    line.valid?
    assert_equal :vendor, line.vendor_choice
    assert_nil line.other_vendor_name

    assert_equal :other, OrderLine.new(other_vendor_name: "Corner Store").vendor_choice
    assert OrderLine.new.not_sure?
  end

  test "deliveries: all of it is received, less is partly received" do
    with_orders(@world) do
      line = ordered_line(quantity: 4)

      line.record_delivery!(by: @world.requester, quantity: 1)
      assert line.reload.partly_received?
      assert_equal 3, line.outstanding_quantity

      line.record_delivery!(by: @world.requester, quantity: 3, note: "The rest")
      assert line.reload.received?
      assert_equal %w[purchased received received], line.order_request.events.map(&:action).last(3)
    end
  end

  test "a damaged or wrong delivery is a problem" do
    with_orders(@world) do
      line = ordered_line(quantity: 2)
      line.record_delivery!(by: @world.requester, quantity: 2, condition: :damaged, note: "Crushed box")

      assert line.reload.problem?
      assert_equal 2, line.outstanding_quantity
      assert_equal "problem", line.order_request.events.last.action
    end
  end

  test "a delivery is refused for a line that isn't ordered" do
    with_orders(@world) do
      line = approved_request(@world).order_lines.first

      assert_raises(Orders::Refused) { line.record_delivery!(by: @world.requester, quantity: 1) }
    end
  end

  test "a delivery sends order_line_received and runs receiving extensions" do
    with_orders(@world) do
      line = ordered_line(quantity: 1)
      seen = []
      Orders.receiving_extensions.register(:test, partial: "test/fields", after_receive: ->(delivery, params) { seen << [ delivery.quantity, params[:bin] ] })
      received = []
      callback = ->(*, payload) { received << payload.values_at(:order_line, :quantity, :condition, :person) }
      begin
        ActiveSupport::Notifications.subscribed(callback, "order_line_received.gatherpack") do
          line.record_delivery!(by: @world.teammate, quantity: 1, params: { bin: "A1" })
        end
      ensure
        Orders.receiving_extensions.reset!
      end

      assert_equal [ [ 1, "A1" ] ], seen
      assert_equal [ [ line, 1, "good", @world.teammate ] ], received
    end
  end

  test "mark all received records the rest of every open line" do
    with_orders(@world) do
      order_request = approved_request(@world, lines: [ { description: "A", price: 1, quantity: 3 }, { description: "B", price: 1, quantity: 2 } ])
      purchase = buy(@world, order_request.order_lines.to_a)
      order_request.order_lines.first.record_delivery!(by: @world.requester, quantity: 1)

      purchase.reload.mark_all_received!(by: @world.requester)

      assert order_request.reload.order_lines.all?(&:received?)
      assert_equal [ 1, 2, 2 ], OrderDelivery.where(order_line: order_request.order_lines).order(:created_at).pluck(:quantity)
      assert order_request.received?
    end
  end

  test "a buyer can mark a line received without a delivery, with a note" do
    with_orders(@world) do
      line = ordered_line
      assert_raises(Orders::Refused) { line.mark_received!(by: @world.buyer, note: "") }

      line.mark_received!(by: @world.buyer, note: "Handed to the build lead")
      assert line.reload.received?
      assert_empty line.order_deliveries
    end
  end

  test "backordered with an expected date" do
    with_orders(@world) do
      line = ordered_line
      line.backorder!(by: @world.buyer, expected_on: Date.new(2027, 1, 15))

      assert line.reload.backordered?
      assert_equal Date.new(2027, 1, 15), line.expected_on
      assert_equal "backordered", line.order_request.events.last.action
      line.record_delivery!(by: @world.requester, quantity: 4)
      assert line.reload.received?
    end
  end

  test "split keeps part now and puts the rest on a new line waiting for a buyer" do
    with_orders(@world) do
      line = approved_request(@world, lines: [ { description: "Wheel", price: 5, quantity: 10 } ]).order_lines.first
      assert_raises(Orders::Refused) { line.split!(10, by: @world.buyer) }

      rest = line.split!(4, by: @world.buyer)

      assert_equal [ 4, 6 ], [ line.reload.quantity, rest.quantity ]
      assert rest.approved?
      assert_equal line.order_request_id, rest.order_request_id
      assert_equal 5000, line.order_request.reload.total_cents
    end
  end

  test "cancelling a line needs a reason" do
    with_orders(@world) do
      line = approved_request(@world).order_lines.first
      assert_raises(Orders::Refused) { line.cancel!(by: @world.buyer, reason: "") }

      line.cancel!(by: @world.buyer, reason: "Discontinued")
      assert line.reload.cancelled?
      assert_equal "Discontinued", line.order_request.events.last.comment
      assert line.order_request.reload.cancelled?, "with every line cancelled the request is cancelled"
    end
  end

  test "lowering a quantity after approval needs no approval; raising it past the tolerance does" do
    with_orders(@world, orders_price_tolerance: "10%, 25") do
      line = approved_request(@world, lines: [ { description: "Servo", price: 20, quantity: 5 } ]).order_lines.first

      line.change_quantity!(4, by: @world.buyer)
      assert line.reload.approved?

      line.change_quantity!(5, by: @world.buyer)  # back to $100: within $25 of the approved $100
      assert line.reload.approved?

      line.change_quantity!(7, by: @world.buyer)  # $140
      assert line.reload.needs_reapproval?
      order_request = line.order_request.reload
      assert order_request.approved?, "needs_reapproval leaves the request status alone"
      assert_equal "reapproval_needed", order_request.events.last.action
    end
  end

  test "a problem is resolved by reordering like for like, with no new approval" do
    with_orders(@world) do
      line = ordered_line(quantity: 3)
      line.record_delivery!(by: @world.requester, quantity: 1)
      line.record_delivery!(by: @world.requester, quantity: 2, condition: :wrong_item)

      replacement = line.reload.resolve_problem!(:reorder, by: @world.buyer)

      assert line.reload.received?, "one arrived good, so this line is finished"
      assert replacement.approved?
      assert_equal [ 2, line.description, line.vendor_id ], [ replacement.quantity, replacement.description, replacement.vendor_id ]
      assert line.order_request.reload.ordering?
    end
  end

  test "a problem can be cancelled, with a reason" do
    with_orders(@world) do
      line = ordered_line(quantity: 1)
      line.record_delivery!(by: @world.requester, quantity: 1, condition: :damaged)
      assert_raises(Orders::Refused) { line.reload.resolve_problem!(:cancel, by: @world.buyer) }

      line.reload.resolve_problem!(:cancel, by: @world.buyer, comment: "Not worth it")
      assert line.reload.cancelled?
    end
  end

  test "the ordered hook fires once for a purchase past the tolerance and its re-approval" do
    with_orders(@world, orders_price_tolerance: "10%, 25") do
      order_request = approved_request(@world, lines: [ { description: "Kit", price: 100 } ])
      line = order_request.order_lines.first
      fired = []
      original = Orders.method(:run_hooks)
      Orders.define_singleton_method(:run_hooks) { |event, record| fired << event }
      begin
        buy(@world, [ line ], prices: { line.id => 20_000 })
        assert line.reload.needs_reapproval?
        order_request.reload.decide!(:approved, by: @world.mentor)
        assert line.reload.ordered?
      ensure
        Orders.define_singleton_method(:run_hooks, original)
      end

      assert_equal [ "order_lines - ordered" ], fired
    end
  end

  test "line status hooks fire for ordered and received" do
    with_orders(@world) do
      order_request = approved_request(@world)
      fired = []
      original = Orders.method(:run_hooks)
      Orders.define_singleton_method(:run_hooks) { |event, record| fired << event }
      begin
        buy(@world, order_request.order_lines.to_a)
        order_request.order_lines.first.reload.record_delivery!(by: @world.requester, quantity: 1)
      ensure
        Orders.define_singleton_method(:run_hooks, original)
      end

      assert_equal [ "order_lines - ordered", "order_lines - received" ], fired
    end
  end
end
