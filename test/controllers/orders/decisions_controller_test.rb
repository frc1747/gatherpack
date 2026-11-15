require "test_helper"
require "support/orders_world"

class Orders::DecisionsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include OrdersWorld

  setup { @world = build_orders_world }

  test "an approver approves the final step" do
    with_orders(@world) do
      order_request = submitted_request(@world)
      sign_in @world.mentor.user

      post orders_request_decisions_url(order_request), params: { decision: "approved", comment: "Fine" }

      assert_redirected_to orders_approvals_url
      assert_equal "Approved: #{order_request.display_title}", flash[:notice]
      assert order_request.reload.approved?
      assert_equal "Fine", order_request.events.last.comment
      assert_equal @world.mentor, order_request.events.last.actor
    end
  end

  test "approving the first of two steps leaves the request waiting on the second" do
    with_settings(two_step_settings(@world, minimum: 5)) do
      Orders::Current.reset
      order_request = submitted_request(@world, lines: [ { description: "Kit", price: 10 } ])
      sign_in @world.mentor.user

      post orders_request_decisions_url(order_request), params: { decision: "approved" }

      assert order_request.reload.submitted?
      assert_equal "treasurer", order_request.current_step.key
    end
  end

  test "asking for changes needs a comment and sends it back to the requester" do
    with_orders(@world) do
      order_request = submitted_request(@world)
      sign_in @world.mentor.user

      post orders_request_decisions_url(order_request), params: { decision: "changes_requested", comment: "" }
      assert_equal "Say what needs changing or why it's declined.", flash[:alert]
      assert order_request.reload.submitted?

      post orders_request_decisions_url(order_request), params: { decision: "changes_requested", comment: "Which size?" }
      assert order_request.reload.changes_requested?
      assert_equal "Which size?", order_request.events.last.comment
    end
  end

  test "declining needs a comment and is final" do
    with_orders(@world) do
      order_request = submitted_request(@world)
      sign_in @world.mentor.user

      post orders_request_decisions_url(order_request), params: { decision: "declined" }
      assert order_request.reload.submitted?

      post orders_request_decisions_url(order_request), params: { decision: "declined", comment: "Not this season" }
      assert order_request.reload.declined?
    end
  end

  test "an unknown decision is refused" do
    with_orders(@world) do
      order_request = submitted_request(@world)
      sign_in @world.mentor.user

      post orders_request_decisions_url(order_request), params: { decision: "maybe" }

      assert_equal "Unknown decision.", flash[:alert]
      assert order_request.reload.submitted?
    end
  end

  test "an approver can't decide their own request" do
    with_orders(@world) do
      order_request = submitted_request(@world, by: @world.mentor)
      sign_in @world.mentor.user

      post orders_request_decisions_url(order_request), params: { decision: "approved" }

      assert_equal "You made this request, so another approver has to decide.", flash[:alert]
      assert order_request.reload.submitted?
    end
  end

  test "an approver can't decide a relative's request" do
    with_orders(@world) do
      order_request = submitted_request(@world)
      sign_in @world.parent.user

      post orders_request_decisions_url(order_request), params: { decision: "declined", comment: "No" }

      assert_equal "A relative made this request, so another approver has to decide.", flash[:alert]
      assert order_request.reload.submitted?
    end
  end

  test "following a request doesn't stop an approver deciding it" do
    with_orders(@world) do
      order_request = submitted_request(@world)
      order_request.follow!(@world.mentor)
      sign_in @world.mentor.user

      post orders_request_decisions_url(order_request), params: { decision: "approved" }

      assert order_request.reload.approved?
    end
  end

  test "someone who isn't an approver is refused, and someone who can't see the request gets nothing" do
    with_orders(@world) do
      order_request = submitted_request(@world)

      sign_in @world.teammate.user
      post orders_request_decisions_url(order_request), params: { decision: "approved" }
      assert_match "You aren't an approver", flash[:alert]
      assert order_request.reload.submitted?

      sign_in @world.outsider.user
      post orders_request_decisions_url(order_request), params: { decision: "approved" }
      assert_response :not_found
      assert order_request.reload.submitted?
    end
  end

  test "a request that's no longer waiting can't be decided again" do
    with_orders(@world) do
      order_request = approved_request(@world)
      sign_in @world.admin.user

      post orders_request_decisions_url(order_request), params: { decision: "declined", comment: "Changed my mind" }

      assert_equal "Nothing is waiting for a decision.", flash[:alert]
      assert order_request.reload.approved?
    end
  end

  test "a restricted source needs the fits tick to approve, and the tick goes in the timeline" do
    with_orders(@world) do
      grant = FundingSource.create!(team: @world.robotics, name: "Parts grant", kind: :restricted, restriction: "Robot parts only")
      order_request = submitted_request(@world)
      order_request.update!(funding_source: grant)
      sign_in @world.mentor.user

      post orders_request_decisions_url(order_request), params: { decision: "approved" }
      assert_equal "Confirm the request fits the funding restriction.", flash[:alert]
      assert order_request.reload.submitted?

      post orders_request_decisions_url(order_request), params: { decision: "approved", fits_restriction: "1" }
      assert order_request.reload.approved?
      assert_equal true, order_request.events.last.field_changes["fits_restriction"]
    end
  end

  test "the approver picks a funding source while approving" do
    with_orders(@world, orders_require_funding_source: "true") do
      budget = FundingSource.create!(team: @world.club, name: "Club budget")
      order_request = submitted_request(@world)
      sign_in @world.mentor.user

      post orders_request_decisions_url(order_request), params: { decision: "approved" }
      assert_equal "Choose a funding source before the final approval.", flash[:alert]

      post orders_request_decisions_url(order_request), params: { decision: "approved", funding_source_id: budget.id }
      assert order_request.reload.approved?
      assert_equal budget, order_request.funding_source
    end
  end

  test "a restricted source picked without the tick is kept, so the page shows its restriction" do
    with_orders(@world) do
      grant = FundingSource.create!(team: @world.robotics, name: "Parts grant", kind: :restricted, restriction: "Robot parts only")
      order_request = submitted_request(@world)
      sign_in @world.mentor.user

      post orders_request_decisions_url(order_request), params: { decision: "approved", funding_source_id: grant.id }

      assert_equal "Confirm the request fits the funding restriction.", flash[:alert]
      assert order_request.reload.submitted?
      assert_equal grant, order_request.funding_source
    end
  end

  test "a source the request's team can't use isn't picked" do
    with_orders(@world) do
      art_budget = FundingSource.create!(team: @world.art, name: "Art budget")
      order_request = submitted_request(@world)
      sign_in @world.mentor.user

      post orders_request_decisions_url(order_request), params: { decision: "approved", funding_source_id: art_budget.id }

      assert_match "can't be used by", flash[:alert]
      assert_nil order_request.reload.funding_source
      assert order_request.submitted?
    end
  end

  test "re-approval: approving keeps the changed items, declining cancels them, asking for changes is refused" do
    with_settings(orders_settings(@world, orders_price_tolerance: "10%, 25")) do
      Orders::Current.reset
      kept = approved_request(@world, lines: [ { description: "Kit", price: 100 } ])
      buy(@world, kept.order_lines.to_a, prices: { kept.order_lines.first.id => 13_000 })
      dropped = approved_request(@world, lines: [ { description: "Motor", price: 100 } ])
      buy(@world, dropped.order_lines.to_a, prices: { dropped.order_lines.first.id => 13_000 })
      sign_in @world.mentor.user

      post orders_request_decisions_url(kept), params: { decision: "changes_requested", comment: "Hmm" }
      assert_equal "Approve or decline the changed items.", flash[:alert]
      assert kept.reload.needs_reapproval?

      post orders_request_decisions_url(kept), params: { decision: "approved" }
      assert kept.order_lines.first.reload.ordered?

      post orders_request_decisions_url(dropped), params: { decision: "declined", comment: "Too dear" }
      assert dropped.order_lines.first.reload.cancelled?
    end
  end

  test "decisions are turned away while the feature is off" do
    order_request = with_orders(@world) { submitted_request(@world) }
    sign_in @world.mentor.user

    with_settings(orders_settings(@world, feature_orders: "false")) do
      post orders_request_decisions_url(order_request), params: { decision: "approved" }
      assert_redirected_to root_url
    end
    assert order_request.reload.submitted?
  end
end
