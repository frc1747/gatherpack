require "test_helper"
require "support/orders_world"

class Orders::DeliveriesControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include OrdersWorld

  PIXEL = Base64.decode64("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGP4z8DwHwAFAAH/q842iQAAAABJRU5ErkJggg==")

  setup { @world = build_orders_world }

  # An approved request bought from one purchase.
  def ordered_request(lines: [ { description: "Gear", quantity: 3, price: 10 }, { description: "Belt", price: 5 } ], **attributes)
    order_request = approved_request(@world, lines: lines, **attributes)
    purchase = buy(@world, order_request.order_lines.to_a, vendor: @world.preferred_vendor)
    [ order_request.reload, purchase ]
  end

  def delivery_params(**overrides)
    { order_delivery: { quantity: 3, received_on: Date.current.to_s, delivery_problem_kind_id: "", note: "" }.merge(overrides) }
  end

  test "To receive lists open items by purchase, and mine=1 only own and followed requests" do
    with_orders(@world) do
      ordered_request(title: "Mine")
      other, = ordered_request(by: @world.teammate, title: "Teammate's order")
      sign_in @world.requester.user

      get orders_deliveries_url
      assert_response :success
      assert_select "a", text: "Receive", count: 4

      get orders_deliveries_url(mine: 1)
      assert_select "a", text: "Receive", count: 2
      assert_no_match "Teammate&#39;s order", response.body

      other.follow!(@world.requester)
      get orders_deliveries_url(mine: 1)
      assert_select "a", text: "Receive", count: 4
    end
  end

  test "the mine=1 list holds as many items as WaitingOn counts for the viewer" do
    with_orders(@world) do
      ordered_request
      ordered_request(by: @world.teammate)
      draft_request(@world)
      receiving = Orders::Receiving.new(@world.requester.user, policy_scope_for(@world.requester), mine: true)
      assert_equal Orders::WaitingOn.new(@world.requester).lines_to_receive, receiving.count
      assert_equal 2, receiving.count
    end
  end

  test "To receive runs the same queries however many items it lists" do
    with_orders(@world) do
      2.times { ordered_request }
      sign_in @world.requester.user
      get orders_deliveries_url(mine: 1)

      # The orders tables are what grows with the list; the layout's own
      # lookups (theme, logo) aren't counted. The query cache lives across
      # requests in a test, so each count starts from an empty one: otherwise
      # a lookup that runs once per request (the grants' team by name) counts
      # or not depending on what the request before it, or a write since,
      # left in the cache.
      count = lambda do
        ActiveRecord::Base.clear_query_caches_for_current_thread
        queries = 0
        counter = ->(*, payload) { queries += 1 if payload[:sql].match?(/FROM "(order_\w+|purchases|vendors|teams)"/) && !payload[:cached] }
        ActiveSupport::Notifications.subscribed(counter, "sql.active_record") { get orders_deliveries_url(mine: 1) }
        queries
      end
      before = count.call
      3.times { ordered_request }
      assert_equal before, count.call
      assert_select "a", text: "Receive", count: 10
    end
  end

  test "someone who can't receive doesn't see the items" do
    with_orders(@world) do
      ordered_request
      sign_in @world.outsider.user

      get orders_deliveries_url
      assert_response :success
      assert_select "a", text: "Receive", count: 0
    end
  end

  test "the delivery dialog asks for quantity, date, condition, note and a photo" do
    with_orders(@world) do
      order_request, = ordered_request
      line = order_request.order_lines.find_by(description: "Gear")
      sign_in @world.requester.user

      get new_orders_request_line_delivery_url(order_request, line)
      assert_response :success
      assert_select "input[name='order_delivery[quantity]'][value='3']"
      assert_select "input[name='order_delivery[received_on]']"
      assert_select "select[name='order_delivery[delivery_problem_kind_id]'] option[selected]", 0
      assert_select "select[name='order_delivery[delivery_problem_kind_id]'] option", 3
      assert_select "select[name='order_delivery[delivery_problem_kind_id]'] option[value='']", "Good"
      assert_select "textarea[name='order_delivery[note]']"
      assert_select "input[type=file][name='order_delivery[photo]']"
    end
  end

  test "a receiving extension adds fields to the dialog and is called with the saved delivery" do
    called = []
    original_paths = ActionController::Base.view_paths
    ActionController::Base.prepend_view_path Rails.root.join("test/support/views")
    Orders.receiving_extensions.register(:test_put_away, partial: "orders/deliveries/test_put_away",
      after_receive: ->(delivery, params) { called << [ delivery, params.dig(:order_delivery, :put_away) ] })
    with_orders(@world) do
      order_request, = ordered_request
      line = order_request.order_lines.find_by(description: "Gear")
      sign_in @world.requester.user

      get new_orders_request_line_delivery_url(order_request, line)
      assert_select "input[name='order_delivery[put_away]']"

      post orders_request_line_deliveries_url(order_request, line), params: delivery_params(put_away: "Shelf 2")
      assert_redirected_to orders_request_url(order_request)
      assert_equal 1, called.size
      delivery, put_away = called.first
      assert delivery.persisted?
      assert_equal line, delivery.order_line
      assert_equal 3, delivery.quantity
      assert_equal "Shelf 2", put_away
    end
  ensure
    Orders.receiving_extensions.reset!
    ActionController::Base.view_paths = original_paths
  end

  test "receiving the full quantity makes the item here, less makes it partly here" do
    with_orders(@world) do
      order_request, = ordered_request
      line = order_request.order_lines.find_by(description: "Gear")
      sign_in @world.requester.user

      post orders_request_line_deliveries_url(order_request, line), params: delivery_params(quantity: 1)
      assert line.reload.partly_received?

      post orders_request_line_deliveries_url(order_request, line), params: delivery_params(quantity: 2, note: "Rest came")
      assert line.reload.received?
      assert_equal [ 1, 2 ], line.order_deliveries.map(&:quantity)
    end
  end

  test "a damaged delivery makes the item a problem" do
    with_orders(@world) do
      order_request, = ordered_request
      line = order_request.order_lines.find_by(description: "Gear")
      sign_in @world.requester.user

      post orders_request_line_deliveries_url(order_request, line), params: delivery_params(delivery_problem_kind_id: DeliveryProblemKind.find_by!(key: "damaged").id, note: "Crushed box")
      assert line.reload.problem?
      assert_equal "Damaged", line.order_deliveries.last.condition_name
    end
  end

  test "a photo is kept with the delivery" do
    with_orders(@world) do
      order_request, = ordered_request
      line = order_request.order_lines.find_by(description: "Gear")
      sign_in @world.requester.user

      post orders_request_line_deliveries_url(order_request, line),
        params: delivery_params(photo: Rack::Test::UploadedFile.new(StringIO.new(PIXEL), "image/png", true, original_filename: "box.png"))
      assert line.order_deliveries.last.photo.attached?
    end
  end

  test "a bad quantity shows the form again" do
    with_orders(@world) do
      order_request, = ordered_request
      line = order_request.order_lines.find_by(description: "Gear")
      sign_in @world.requester.user

      post orders_request_line_deliveries_url(order_request, line), params: delivery_params(quantity: 0)
      assert_response :unprocessable_entity
      assert line.reload.ordered?
    end
  end

  test "someone who can't receive for the request is turned away" do
    with_orders(@world) do
      order_request, = ordered_request
      line = order_request.order_lines.first
      sign_in @world.outsider.user

      post orders_request_line_deliveries_url(order_request, line), params: delivery_params
      assert_response :not_found
      assert line.reload.ordered?
    end
  end

  test "a team member can receive when team members can see requests, and not when they can't" do
    with_orders(@world) do
      order_request, = ordered_request
      line = order_request.order_lines.find_by(description: "Gear")
      sign_in @world.teammate.user

      post orders_request_line_deliveries_url(order_request, line), params: delivery_params(quantity: 1)
      assert line.reload.partly_received?
    end

    with_orders(@world, orders_team_can_see: "false") do
      order_request, = ordered_request
      line = order_request.order_lines.find_by(description: "Gear")
      post orders_request_line_deliveries_url(order_request, line), params: delivery_params(quantity: 1)
      assert_response :not_found
      assert line.reload.ordered?
    end
  end

  test "mark all received on a request receives every open item" do
    with_orders(@world) do
      order_request, = ordered_request
      sign_in @world.requester.user

      post mark_all_received_orders_request_url(order_request)
      assert_redirected_to orders_request_url(order_request)
      assert order_request.reload.order_lines.all?(&:received?)
      assert order_request.received?
    end
  end

  test "mark all received on a purchase skips requests the viewer can't receive for" do
    with_orders(@world, orders_team_can_see: "false") do
      mine = approved_request(@world, lines: [ { description: "Mine", price: 5 } ])
      theirs = approved_request(@world, lines: [ { description: "Theirs", price: 5 } ], by: @world.teammate)
      purchase = buy(@world, mine.order_lines.to_a + theirs.order_lines.to_a, vendor: @world.preferred_vendor)
      sign_in @world.requester.user

      post mark_all_received_orders_purchase_url(purchase)
      assert mine.reload.order_lines.all?(&:received?)
      assert theirs.reload.order_lines.all?(&:ordered?)
    end
  end

  test "mark all received on a purchase from the mine=1 list leaves other people's items alone" do
    with_orders(@world) do
      mine = approved_request(@world, lines: [ { description: "Mine", price: 5 } ])
      theirs = approved_request(@world, lines: [ { description: "Theirs", price: 5 } ], by: @world.teammate)
      purchase = buy(@world, mine.order_lines.to_a + theirs.order_lines.to_a, vendor: @world.preferred_vendor)
      sign_in @world.requester.user

      post mark_all_received_orders_purchase_url(purchase, mine: 1, from: "list")
      assert_redirected_to orders_deliveries_url(mine: 1)
      assert mine.reload.order_lines.all?(&:received?)
      assert theirs.reload.order_lines.all?(&:ordered?)
    end
  end

  test "a partly damaged item can still have the rest received, from the list and the request page" do
    with_orders(@world) do
      order_request, = ordered_request
      line = order_request.order_lines.find_by(description: "Gear")
      line.record_delivery!(by: @world.requester, quantity: 1, condition: :damaged, note: "Cracked")
      sign_in @world.requester.user

      get orders_deliveries_url(mine: 1)
      assert_select "a", text: "Receive", count: 2
      assert_equal Orders::WaitingOn.new(@world.requester).lines_to_receive, 2

      get orders_request_url(order_request)
      assert_select "a", text: /Receive the rest \(2 to come\)/
      get new_orders_request_line_delivery_url(order_request, line)
      assert_select "input[name='order_delivery[quantity]'][value='2']"

      post orders_request_line_deliveries_url(order_request, line), params: delivery_params(quantity: 2)
      assert line.reload.problem?, "still a problem until the buyer settles the damaged one"
      assert_not line.open_to_receive?, "the 2 good ones were the 2 coming"
      get orders_deliveries_url(mine: 1)
      assert_select "a", text: "Receive", count: 1
      assert_equal 1, Orders::WaitingOn.new(@world.requester).lines_to_receive
    end
  end

  test "an item that all came damaged isn't on To receive or in the count, and has no Mark all button" do
    with_orders(@world) do
      order_request = approved_request(@world, lines: [ { description: "Gear", quantity: 3, price: 10 } ])
      buy(@world, order_request.order_lines.to_a, vendor: @world.preferred_vendor)
      line = order_request.order_lines.first
      line.record_delivery!(by: @world.requester, quantity: 3, condition: :damaged)
      sign_in @world.requester.user

      get orders_deliveries_url(mine: 1)
      assert_select "a", text: "Receive", count: 0
      assert_select "button", text: "Mark all received", count: 0
      assert_equal 0, Orders::WaitingOn.new(@world.requester).lines_to_receive

      get orders_request_url(order_request)
      assert_select "a", text: /Receive the rest/, count: 0
    end
  end

  test "Mark all received shows on an order only when it has an item it can receive" do
    with_orders(@world) do
      order_request, = ordered_request
      order_request.order_lines.find_by(description: "Gear").record_delivery!(by: @world.requester, quantity: 1, condition: :damaged)
      sign_in @world.requester.user

      get orders_deliveries_url(mine: 1)
      assert_select "button", text: "Mark all received", count: 1
    end
  end

  test "mark all received leaves a problem item for the buyer" do
    with_orders(@world) do
      order_request, = ordered_request
      line = order_request.order_lines.find_by(description: "Gear")
      line.record_delivery!(by: @world.requester, quantity: 1, condition: :damaged)
      sign_in @world.requester.user

      post mark_all_received_orders_request_url(order_request)
      assert line.reload.problem?
      assert order_request.order_lines.find_by(description: "Belt").received?
    end
  end

  test "the request page leaves room under the fixed bar once, at the end of the page" do
    with_orders(@world) do
      order_request, = ordered_request
      sign_in @world.requester.user

      get orders_request_url(order_request)
      assert_select "div.pb-5.mb-4", count: 1
      assert_select "#receiving div.pb-5", count: 0
    end
  end

  test "mark all received on a purchase is refused when there is nothing the viewer may receive" do
    with_orders(@world) do
      _, purchase = ordered_request
      sign_in @world.outsider.user

      post mark_all_received_orders_purchase_url(purchase)
      assert_response :not_found
    end
  end

  test "the turned-off feature turns receiving away" do
    sign_in @world.requester.user
    with_settings(orders_settings(@world, feature_orders: "false")) do
      get orders_deliveries_url
      assert_redirected_to root_url
    end
  end

  test "the request page shows receiving, and a buyer's actions on a problem" do
    with_orders(@world) do
      order_request, = ordered_request
      line = order_request.order_lines.find_by(description: "Gear")
      sign_in @world.requester.user

      get orders_request_url(order_request)
      assert_select "#receiving"
      assert_select "button", text: "Mark all received"
      assert_select "input[value='Already got it']", count: 0

      line.record_delivery!(by: @world.requester, quantity: 1, condition: :damaged, note: "Cracked")
      get orders_request_url(order_request)
      assert_match "Cracked", response.body
      assert_select "button", text: "Order a replacement", count: 0

      sign_in @world.buyer.user
      get orders_request_url(order_request)
      assert_select "button", text: "Order a replacement"
      assert_select "input[value='Already got it']"
    end
  end

  private

  def policy_scope_for(person)
    OrderRequestPolicy::Scope.new(person.user, OrderRequest).resolve
  end
end
