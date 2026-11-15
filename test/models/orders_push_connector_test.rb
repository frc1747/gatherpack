require "test_helper"
require "support/orders_world"
require "support/order_notices_helper"
require "support/push_connector_test_support"

class OrdersPushConnectorTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper
  include OrdersWorld
  include OrderNoticesHelper
  include PushConnectorTestSupport

  setup do
    @world = build_orders_world
    @requester = @world.requester
    create_push_gateway
  end

  PUSH_ON = { feature_phone_notifications: "true", feature_installable_app: "true" }.freeze

  def with_push(**overrides, &block)
    with_orders(@world, **PUSH_ON, **overrides, &block)
  end

  def opt_in(*people)
    people.each { |person| subscribe(person, :orders) }
  end

  def user_ids(*people)
    people.map { |person| person.user.id }.sort
  end

  test "a submitted request is pushed to the approvers who opted in, and no one else" do
    with_push do
      draft = draft_request(@world)
      opt_in @world.mentor, @world.requester, @world.outsider
      clear_enqueued_jobs
      draft.submit!(by: @requester)

      assert_equal user_ids(@world.mentor), pushed_user_ids
      assert_equal [ "To approve: Gear" ], push_titles
      assert_equal [ "/orders/requests/#{draft.to_param}" ], push_paths
    end
  end

  test "the same people are emailed and pushed to, with an email for each" do
    with_push do
      draft = draft_request(@world)
      opt_in @world.mentor, @world.manager, @world.admin
      clear_enqueued_jobs
      draft.submit!(by: @requester)

      assert_equal user_ids(@world.mentor, @world.manager, @world.admin), pushed_user_ids
      assert_equal addresses(@world.mentor, @world.manager, @world.admin), emailed
    end
  end

  test "a decision is pushed to the requester, not to the person who made it" do
    with_push do
      request = submitted_request(@world)
      opt_in @world.requester, @world.mentor
      clear_enqueued_jobs
      request.decide!(:declined, by: @world.mentor, comment: "No")

      assert_equal user_ids(@world.requester), pushed_user_ids
      assert_equal [ "Declined: Gear" ], push_titles
    end
  end

  test "a notice about a line opens its request" do
    with_push do
      request = approved_request(@world)
      line = request.order_lines.first
      opt_in @world.buyer
      clear_enqueued_jobs
      purchase = buy(@world, [ line ])
      opt_in @world.requester
      clear_enqueued_jobs
      OrderNotices.new.backordered(line, by: @world.buyer)

      assert_equal user_ids(@world.requester), pushed_user_ids
      assert_equal [ "/orders/requests/#{request.to_param}" ], push_paths
      assert purchase
    end
  end

  test "the buyers' digest opens To buy" do
    with_push do
      request = approved_request(@world)
      opt_in @world.buyer
      clear_enqueued_jobs
      OrderNotices.new.buyer_digest(@world.buyer, [ request ])

      assert_equal user_ids(@world.buyer), pushed_user_ids
      assert_equal [ "/orders/purchases/to_buy" ], push_paths
    end
  end

  test "people who haven't chosen the orders topic get no push" do
    with_push do
      draft = draft_request(@world)
      subscribe @world.mentor, :forms
      clear_enqueued_jobs
      draft.submit!(by: @requester)

      assert_empty enqueued_pushes
      assert_equal addresses(@world.mentor, @world.manager, @world.admin), emailed
    end
  end

  test "nothing is pushed with phone notifications off, and the emails still go" do
    with_push(feature_phone_notifications: "false") do
      draft = draft_request(@world)
      opt_in @world.mentor
      clear_enqueued_jobs
      draft.submit!(by: @requester)

      assert_empty enqueued_pushes
      assert_equal addresses(@world.mentor, @world.manager, @world.admin), emailed
    end
  end

  test "nothing is pushed or emailed while orders is off" do
    with_push do
      draft = draft_request(@world)
      opt_in @world.mentor
      clear_enqueued_jobs
      with_settings(feature_orders: "false") { OrderNotices.new.submitted(draft, by: @requester) }

      assert_empty enqueued_pushes
      assert_empty enqueued_emails
    end
  end

  test "a push doesn't need an email address" do
    with_push do
      draft = draft_request(@world)
      @world.mentor.user.update_columns(email: "")
      opt_in @world.mentor
      clear_enqueued_jobs
      draft.submit!(by: @requester)

      assert_equal user_ids(@world.mentor), pushed_user_ids
      assert_not_includes emailed, ""
    end
  end

  test "the emails go and nothing raises when push fails" do
    with_push do
      draft = draft_request(@world)
      opt_in @world.mentor
      clear_enqueued_jobs

      replacing(GatherPack::PushChannel, :deliver, ->(*, **) { raise "push is down" }) do
        assert_nothing_raised { draft.submit!(by: @requester) }
      end
      assert_equal addresses(@world.mentor, @world.manager, @world.admin), emailed
    end
  end

  test "the orders topic is offered only while orders is on" do
    with_settings(feature_orders: "true") { assert_includes GatherPack::PushTopics.keys, :orders }
    with_settings(feature_orders: "false") { assert_not_includes GatherPack::PushTopics.keys, :orders }
  end
end
