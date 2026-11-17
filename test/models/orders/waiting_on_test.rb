require "test_helper"
require "support/orders_world"

class Orders::WaitingOnTest < ActiveSupport::TestCase
  include OrdersWorld

  setup { @world = build_orders_world }

  def waiting(person)
    Orders::Current.reset
    Orders::WaitingOn.new(person)
  end

  def kinds(person)
    waiting(person).todos.map(&:kind)
  end

  test "an approver on the current step gets a review row; others don't" do
    with_orders(@world) do
      order_request = submitted_request(@world)

      assert_equal [ order_request ], waiting(@world.mentor).to_approve
      assert_equal [ :approve ], kinds(@world.mentor)
      assert_equal [ :approve ], kinds(@world.manager)
      assert_empty kinds(@world.teammate)
      assert_empty kinds(@world.outsider)
      assert_empty kinds(@world.buyer)
    end
  end

  test "a requester never gets an approval row for their own or a relative's request" do
    with_orders(@world) do
      submitted_request(@world, by: @world.mentor)
      submitted_request(@world, by: @world.requester)

      mentor_rows = waiting(@world.mentor).to_approve
      assert_equal [ @world.requester ], mentor_rows.map(&:requested_by)
      assert_empty waiting(@world.parent).to_approve.select { |r| r.requested_by == @world.requester }
      assert_equal [ @world.mentor ], waiting(@world.parent).to_approve.map(&:requested_by)
    end
  end

  test "approvers only see a request on the step they can decide" do
    with_settings(two_step_settings(@world, minimum: 500)) do
      Orders::Current.reset
      order_request = submitted_request(@world, lines: [ { description: "Kit", price: 600 } ])
      assert_equal [ :approve ], kinds(@world.mentor)

      order_request.decide!(:approved, by: @world.mentor)
      assert_empty kinds(@world.mentor)
      assert_equal [ :approve ], kinds(@world.manager)
    end
  end

  test "the final step's approvers get a row for a line needing re-approval" do
    with_orders(@world) do
      order_request = approved_request(@world, lines: [ { description: "Kit", price: 100 } ])
      order_request.order_lines.first.change_quantity!(3, by: @world.buyer)

      assert_equal [ :reapprove ], kinds(@world.mentor)
      assert_empty kinds(@world.teammate)
    end
  end

  test "the requester gets an update row with the approver's comment when changes are requested" do
    with_orders(@world) do
      order_request = submitted_request(@world)
      order_request.decide!(:changes_requested, by: @world.mentor, comment: "Which size?")

      rows = waiting(@world.requester).todos
      assert_equal [ :update ], rows.map(&:kind)
      assert_equal "Which size?", rows.first.comment
      assert_empty kinds(@world.teammate)
    end
  end

  test "30 lines to buy are one row for a buyer" do
    with_orders(@world) do
      approved_request(@world, lines: Array.new(30) { |i| { description: "Part #{i}", price: 1 } }, needed_by: Date.current + 3)

      rows = waiting(@world.buyer).todos
      assert_equal [ :buy ], rows.map(&:kind)
      assert_equal 30, rows.first.count
      assert_equal Date.current + 3, rows.first.needed_by
      assert_equal 30, waiting(@world.buyer).lines_to_buy
      assert_equal 0, waiting(@world.teammate).lines_to_buy
      assert_equal 0, waiting(@world.outsider).lines_to_buy
    end
  end

  test "the buyer of a line with a problem gets a resolve row" do
    with_orders(@world) do
      order_request = approved_request(@world)
      buy(@world, order_request.order_lines.to_a)
      order_request.order_lines.first.reload.record_delivery!(by: @world.requester, quantity: 1, condition: :damaged)

      assert_includes kinds(@world.buyer), :resolve
      assert_not_includes kinds(@world.manager), :resolve
    end
  end

  test "the requester and followers get a receive row; team members who can receive don't" do
    with_orders(@world) do
      order_request = approved_request(@world, lines: [ { description: "A", price: 1 }, { description: "B", price: 1 }, { description: "C", price: 1 } ])
      order_request.follow!(@world.builder)
      buy(@world, order_request.order_lines.first(2))

      assert_equal 2, waiting(@world.requester).lines_to_receive
      assert_equal [ :receive ], kinds(@world.requester)
      assert_equal [ :receive ], kinds(@world.builder)
      assert_not_includes kinds(@world.teammate), :receive
      assert OrderRequestPolicy.new(@world.teammate.user, order_request).receive?
    end
  end

  test "a draft isn't a to-do, but is an active request for its requester only" do
    with_orders(@world) do
      draft = draft_request(@world)
      draft.follow!(@world.teammate)

      assert_empty kinds(@world.requester)
      assert_equal [ draft ], waiting(@world.requester).active_requests
      assert_empty waiting(@world.teammate).active_requests
    end
  end

  test "active requests are their own and followed ones still going, newest change first" do
    with_orders(@world) do
      mine = submitted_request(@world)
      followed = submitted_request(@world, by: @world.teammate)
      followed.follow!(@world.requester)
      done = approved_request(@world)
      done.cancel!(by: @world.requester)

      assert_equal [ followed, mine ], waiting(@world.requester).active_requests
    end
  end

  test "rows sort by needed_by with none last" do
    with_orders(@world) do
      later = submitted_request(@world, needed_by: Date.current + 10)
      none = submitted_request(@world)
      soon = submitted_request(@world, needed_by: Date.current + 1)

      assert_equal [ soon, later, none ], waiting(@world.mentor).todos.map(&:order_request)
    end
  end

  test "the query count doesn't grow with the number of requests" do
    with_orders(@world) do
      make = lambda do |count|
        count.times do
          order_request = submitted_request(@world, lines: [ { description: "A", price: 1 }, { description: "B", price: 2 } ])
          order_request.follow!(@world.mentor)
        end
        mine = approved_request(@world, lines: [ { description: "C", price: 1 } ])
        buy(@world, mine.order_lines.to_a)
      end

      make.call(2)
      few = count_queries { waiting(@world.mentor).then { |w| [ w.todos, w.active_requests, w.lines_to_buy ] } }
      make.call(10)
      many = count_queries { waiting(@world.mentor).then { |w| [ w.todos, w.active_requests, w.lines_to_buy ] } }

      assert_equal 12, waiting(@world.mentor).to_approve.size
      assert_operator few, :>, 0
      assert_equal few, many
    end
  end

  test "it is memoized for the web request" do
    with_orders(@world) do
      assert_same Orders::WaitingOn.for(@world.mentor), Orders::WaitingOn.for(@world.mentor)
    end
  end

  private

  def count_queries(&block)
    count = 0
    counter = ->(*, payload) { count += 1 unless payload[:name].in?([ "SCHEMA", "TRANSACTION" ]) || payload[:cached] }
    ActiveSupport::Notifications.subscribed(counter, "sql.active_record", &block)
    count
  end
end
