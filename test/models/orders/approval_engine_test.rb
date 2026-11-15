require "test_helper"
require "support/orders_world"

class Orders::ApprovalEngineTest < ActiveSupport::TestCase
  include OrdersWorld

  setup { @world = build_orders_world }

  test "approving the only step approves the request and its lines" do
    with_orders(@world) do
      order_request = submitted_request(@world)
      order_request.decide!(:approved, by: @world.mentor, comment: "Fine")
      order_request.reload

      assert order_request.approved?
      assert_equal 1000, order_request.approved_total_cents
      assert order_request.order_lines.all?(&:approved?)
      event = order_request.events.last
      assert_equal [ "approved", "approval", "Fine", @world.mentor ], [ event.action, event.step_key, event.comment, event.actor ]
    end
  end

  test "a request under a step's minimum needs only the first step" do
    with_settings(two_step_settings(@world, minimum: 500)) do
      Orders::Current.reset
      order_request = submitted_request(@world, lines: [ { description: "Gear", price: 100 } ])

      assert_equal [ "mentor" ], order_request.needed_steps.map(&:key)
      order_request.decide!(:approved, by: @world.mentor)
      assert order_request.reload.approved?
    end
  end

  test "a request over the threshold waits on the second step after the first" do
    with_settings(two_step_settings(@world, minimum: 500)) do
      Orders::Current.reset
      order_request = submitted_request(@world, lines: [ { description: "Robot kit", price: 600 } ])

      assert_equal %w[mentor treasurer], order_request.needed_steps.map(&:key)
      assert_equal "mentor", order_request.current_step.key
      order_request.decide!(:approved, by: @world.mentor)
      order_request.reload

      assert order_request.submitted?
      assert_equal "treasurer", order_request.current_step.key
      assert_not order_request.can_decide?(@world.mentor), "the mentor grant doesn't cover the treasurer step"
      assert order_request.can_decide?(@world.manager)

      order_request.decide!(:approved, by: @world.manager)
      assert order_request.reload.approved?
    end
  end

  test "the threshold is exactly the minimum" do
    with_settings(two_step_settings(@world, minimum: 500)) do
      Orders::Current.reset
      order_request = submitted_request(@world, lines: [ { description: "Kit", price: 500 } ])

      assert_equal 2, order_request.needed_steps.size
    end
  end

  test "asking for changes needs a comment, and resubmitting keeps earlier approvals" do
    with_settings(two_step_settings(@world, minimum: 500)) do
      Orders::Current.reset
      order_request = submitted_request(@world, lines: [ { description: "Kit", price: 600 } ])
      order_request.decide!(:approved, by: @world.mentor)

      assert_raises(Orders::Refused) { order_request.reload.decide!(:changes_requested, by: @world.manager) }
      order_request.reload.decide!(:changes_requested, by: @world.manager, comment: "Which kit?")
      assert order_request.reload.changes_requested?

      order_request.edit!({ purpose: "The blue kit" }, by: @world.requester)
      order_request.resubmit!(by: @world.requester)
      order_request.reload

      assert order_request.submitted?
      assert_equal "treasurer", order_request.current_step.key
    end
  end

  test "declining needs a comment and is final" do
    with_orders(@world) do
      order_request = submitted_request(@world)
      assert_raises(Orders::Refused) { order_request.decide!(:declined, by: @world.mentor) }

      order_request.reload.decide!(:declined, by: @world.mentor, comment: "No budget left")
      assert order_request.reload.declined?
      assert_raises(Orders::Refused) { order_request.decide!(:approved, by: @world.manager) }
      assert_raises(Orders::Refused) { order_request.resubmit!(by: @world.requester) }
    end
  end

  test "an approver can't decide their own request" do
    with_orders(@world) do
      order_request = submitted_request(@world, by: @world.mentor)

      assert_not order_request.can_decide?(@world.mentor)
      assert_match "You made this request", order_request.decision_refusal(@world.mentor)
      assert_raises(Orders::Refused) { order_request.decide!(:approved, by: @world.mentor) }
      assert_raises(Orders::Refused) { order_request.decide!(:declined, by: @world.mentor, comment: "x") }
    end
  end

  test "an approver can't decide a relative's request, in either direction" do
    with_orders(@world) do
      order_request = submitted_request(@world)

      assert_not order_request.can_decide?(@world.parent)
      assert_match "relative", order_request.decision_refusal(@world.parent)
      assert_raises(Orders::Refused) { order_request.decide!(:changes_requested, by: @world.parent, comment: "x") }

      relate(@world.mentor, @world.teammate)
      Orders::Current.reset
      assert_not submitted_request(@world, by: @world.teammate).can_decide?(@world.mentor)
    end
  end

  test "a watcher who holds an approver grant can decide" do
    with_orders(@world) do
      order_request = submitted_request(@world)
      order_request.follow!(@world.mentor)

      assert order_request.reload.can_decide?(@world.mentor)
      order_request.decide!(:approved, by: @world.mentor)
      assert order_request.reload.approved?
    end
  end

  test "someone without an approver grant on the team can't decide" do
    with_orders(@world) do
      order_request = submitted_request(@world)

      assert_not order_request.can_decide?(@world.teammate)
      assert_not order_request.can_decide?(@world.outsider)
      assert order_request.can_decide?(@world.admin)
    end
  end

  test "a material change clears approvals; lowering a quantity doesn't" do
    with_settings(two_step_settings(@world, minimum: 500)) do
      Orders::Current.reset
      order_request = submitted_request(@world, lines: [ { description: "Kit", price: 600, quantity: 2 } ])
      order_request.decide!(:approved, by: @world.mentor)
      line = order_request.reload.order_lines.first

      order_request.edit_line!(line, { quantity: 1 }, by: @world.manager)
      assert_equal 1, order_request.reload.active_approvals.size, "lowering the quantity keeps the approval"
      assert_not order_request.events.last.field_changes.key?("approvals_cleared")

      order_request.reload.edit_line!(line, { quantity: 2 }, by: @world.requester)
      order_request.reload.edit_line!(line, { vendor_part_number: "K-2" }, by: @world.requester)
      order_request.reload

      assert_empty order_request.active_approvals
      assert order_request.order_approvals.first.cleared_at.present?
      assert order_request.events.last.field_changes["approvals_cleared"]
      assert_equal "mentor", order_request.current_step.key
    end
  end

  test "adding a line is a material change" do
    with_settings(two_step_settings(@world, minimum: 500)) do
      Orders::Current.reset
      order_request = submitted_request(@world, lines: [ { description: "Kit", price: 600 } ])
      order_request.decide!(:approved, by: @world.mentor)
      order_request.reload.add_line!({ description: "Battery", estimated_unit_price_cents: 100 }, by: @world.requester)

      assert_empty order_request.reload.active_approvals
    end
  end

  test "raising the total past the tolerance is material; within it isn't" do
    with_settings(two_step_settings(@world, minimum: 500).merge(orders_price_tolerance: "10%, 25")) do
      Orders::Current.reset
      order_request = submitted_request(@world, lines: [ { description: "Kit", price: 600 } ])
      order_request.decide!(:approved, by: @world.mentor)
      line = order_request.reload.order_lines.first

      # Within: $600 → $650 (allowance is 10%, $60)
      order_request.edit_line!(line, { estimated_unit_price_cents: 65_000 }, by: @world.requester)
      assert_equal 1, order_request.reload.active_approvals.size

      # Past it: $600 → $670
      order_request.edit_line!(line, { estimated_unit_price_cents: 67_000 }, by: @world.requester)
      assert_empty order_request.reload.active_approvals
    end
  end

  test "an edit lowering the total under a step's minimum leaves the final step for an approver to confirm" do
    with_settings(two_step_settings(@world, minimum: 500).merge(orders_require_funding_source: "true")) do
      Orders::Current.reset
      order_request = submitted_request(@world, lines: [ { description: "Kit", price: 300, quantity: 2 } ])
      order_request.decide!(:approved, by: @world.mentor)
      order_request.reload.edit_line!(order_request.order_lines.first, { quantity: 1 }, by: @world.manager)
      order_request.reload

      assert order_request.submitted?, "nothing approves itself"
      assert_equal "mentor", order_request.current_step.key
      assert_not_equal "approved", order_request.events.last.action
      assert_raises(Orders::Refused, "the final checks still apply") { order_request.decide!(:approved, by: @world.mentor) }

      source = FundingSource.create!(team: @world.robotics, name: "Build budget")
      order_request.reload.edit!({ funding_source_id: source.id }, by: @world.mentor)
      order_request.reload.decide!(:approved, by: @world.mentor)
      assert order_request.reload.approved?
      assert_equal @world.mentor, order_request.events.last.actor
    end
  end

  test "changing what an item is, or how it's counted, clears approvals" do
    with_settings(two_step_settings(@world, minimum: 500)) do
      Orders::Current.reset
      { description: "Laptop", unit: "pack", units_per: 50 }.each do |field, value|
        order_request = submitted_request(@world, lines: [ { description: "Robot kit", price: 600 } ])
        order_request.decide!(:approved, by: @world.mentor)
        order_request.reload.edit_line!(order_request.order_lines.first, { field => value }, by: @world.requester)

        assert_empty order_request.reload.active_approvals, field
      end
    end
  end

  test "moving a request to another of the requester's teams clears approvals; a team that isn't theirs is refused" do
    with_settings(two_step_settings(@world, minimum: 500)) do
      Orders::Current.reset
      Membership.create!(person: @world.requester, team: @world.build)
      order_request = submitted_request(@world, lines: [ { description: "Kit", price: 600 } ])
      order_request.decide!(:approved, by: @world.mentor)

      assert_raises(ActiveRecord::RecordInvalid) { order_request.reload.edit!({ team_id: @world.art.id }, by: @world.requester) }
      assert_equal @world.robotics.id, order_request.reload.team_id
      assert_equal 1, order_request.active_approvals.size

      order_request.edit!({ team_id: @world.build.id }, by: @world.requester)
      assert_empty order_request.reload.active_approvals
      assert order_request.events.last.field_changes["approvals_cleared"]
    end
  end

  test "moving a request to another team clears funding sources the new team can't use" do
    with_orders(@world) do
      Membership.create!(person: @world.requester, team: @world.art)
      Membership.create!(person: @world.requester, team: @world.build)
      grant = FundingSource.create!(team: @world.robotics, name: "Robotics grant", kind: :restricted, restriction: "Robot parts")
      tools = FundingSource.create!(team: @world.robotics, name: "Robotics tools")
      shared = FundingSource.create!(team: @world.club, name: "Club fund")
      order_request = submitted_request(@world, funding_source: grant,
        lines: [ { description: "Motor", price: 20, funding_source_id: tools.id }, { description: "Glue", price: 2 } ])
      motor = order_request.order_lines.first

      order_request.edit!({ team_id: @world.art.id }, by: @world.requester)
      order_request.reload

      assert_equal @world.art.id, order_request.team_id
      assert_nil order_request.funding_source_id
      assert_nil motor.reload.funding_source_id
      changes = order_request.events.last.field_changes
      assert_equal "edited", order_request.events.last.action
      assert_equal [ grant.id, nil ], changes["funding_source_id"]
      assert_equal({ motor.id => [ tools.id, nil ] }, changes["line_funding_source_ids"])
      assert_empty order_request.restricted_sources

      # A source the new team can still use stays.
      order_request.edit!({ team_id: @world.robotics.id }, by: @world.requester)
      order_request.reload.edit!({ funding_source_id: shared.id }, by: @world.manager)
      order_request.reload.edit!({ team_id: @world.build.id }, by: @world.requester)
      assert_equal shared.id, order_request.reload.funding_source_id
      assert_not order_request.events.last.field_changes.key?("funding_source_id")
    end
  end

  test "a request's funding source must suit its team when the team changes by any route" do
    with_orders(@world) do
      Membership.create!(person: @world.requester, team: @world.art)
      grant = FundingSource.create!(team: @world.robotics, name: "Robotics grant")
      order_request = draft_request(@world, funding_source: grant)

      assert_raises(ActiveRecord::RecordInvalid) { order_request.update!(team: @world.art) }
    end
  end

  test "a request can only be made for one of the requester's teams" do
    with_orders(@world) do
      assert_raises(ActiveRecord::RecordInvalid) { draft_request(@world, team: @world.art) }
      assert draft_request(@world, by: @world.manager, team: @world.build).persisted?, "managers request for teams they manage"
      assert draft_request(@world, by: @world.admin, team: @world.art).persisted?
    end
  end

  test "approving with a restricted source needs the fits-the-restriction tick" do
    with_orders(@world) do
      grant = FundingSource.create!(team: @world.club, name: "Parts grant", kind: :restricted, restriction: "Robot parts only")
      order_request = submitted_request(@world, funding_source: grant)

      assert_raises(Orders::Refused) { order_request.decide!(:approved, by: @world.mentor) }
      order_request.reload.decide!(:approved, by: @world.mentor, fits_restriction: true)

      assert order_request.reload.approved?
      assert_equal true, order_request.events.last.field_changes["fits_restriction"]
    end
  end

  test "a restricted source named only on a line also needs the tick" do
    with_orders(@world) do
      grant = FundingSource.create!(team: @world.robotics, name: "Grant", kind: :restricted, restriction: "Tools")
      order_request = submitted_request(@world, lines: [ { description: "Drill", price: 50, funding_source_id: grant.id } ])

      assert_raises(Orders::Refused) { order_request.decide!(:approved, by: @world.mentor) }
    end
  end

  test "a funding source is required before the final approval only when the setting says so" do
    with_orders(@world, orders_require_funding_source: "true") do
      order_request = submitted_request(@world)
      assert_raises(Orders::Refused) { order_request.decide!(:approved, by: @world.mentor) }

      source = FundingSource.create!(team: @world.robotics, name: "Build budget")
      order_request.reload.edit!({ funding_source_id: source.id }, by: @world.mentor)
      order_request.reload.decide!(:approved, by: @world.mentor)
      assert order_request.reload.approved?
    end
  end

  test "a funding source from an unrelated team can't be used" do
    with_orders(@world) do
      source = FundingSource.create!(team: @world.art, name: "Art budget")

      assert_raises(ActiveRecord::RecordInvalid) { draft_request(@world, funding_source: source) }
    end
  end
end
