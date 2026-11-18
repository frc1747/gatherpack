require "test_helper"
require "support/orders_world"

class ApprovalStepTest < ActiveSupport::TestCase
  include OrdersWorld

  setup { @world = build_orders_world }

  test "a new step gets a key from its name that no step or approval has used" do
    with_orders(@world) do
      OrderApproval.create!(order_request: submitted_request(@world), step_key: "treasurer", approver: @world.mentor, decision: :approved)

      step = ApprovalStep.create!(name: "Treasurer", minimum: "500")

      assert_equal "treasurer_2", step.key
      assert_equal 50_000, step.minimum_cents
    end
  end

  test "the first active step has no minimum: every request needs it" do
    first = ApprovalStep.create!(name: "Approval")
    first.minimum = "100"

    assert_not first.valid?
    assert_includes first.errors[:minimum], "must be $0 for the first step, which every request needs"

    later = ApprovalStep.create!(name: "Treasurer", minimum: "500")
    assert later.valid?
    assert_not later.first?
  end

  test "a step with a minimum that becomes first loses its minimum" do
    first = ApprovalStep.create!(name: "Approval")
    later = ApprovalStep.create!(name: "Treasurer", minimum: "500")

    assert_nil ApprovalStep.free_first_step!
    later.move!(:up)
    assert_equal later, ApprovalStep.free_first_step!
    assert_equal 0, later.reload.minimum_cents
    assert_equal 0, first.reload.minimum_cents
  end

  test "every request needs the first step even when it has a minimum stored" do
    with_settings(two_step_settings(@world, minimum: 500)) do
      Orders::Current.reset
      ApprovalStep.find_by!(key: "mentor").update_column(:minimum_cents, 100_000)
      small = submitted_request(@world, lines: [ { description: "Gear", price: 20 } ])

      assert_equal [ "mentor" ], small.needed_steps.map(&:key)
    end
  end

  test "a request needs the active steps whose minimum it meets, in order" do
    with_settings(two_step_settings(@world, minimum: 500)) do
      Orders::Current.reset
      small = submitted_request(@world, lines: [ { description: "Gear", price: 100 } ])
      large = submitted_request(@world, lines: [ { description: "Robot kit", price: 600 } ])

      assert_equal [ "mentor" ], small.needed_steps.map(&:key)
      assert_equal %w[mentor treasurer], large.needed_steps.map(&:key)

      ApprovalStep.find_by!(key: "treasurer").move!(:up)
      ApprovalStep.free_first_step!
      assert_equal %w[treasurer mentor], large.needed_steps.map(&:key)
      assert_equal %w[treasurer mentor], small.needed_steps.map(&:key), "the first step is needed by every request"

      ApprovalStep.find_by!(key: "treasurer").retire!
      assert_equal [ "mentor" ], large.needed_steps.map(&:key)
    end
  end

  test "renaming a step keeps its approvals and shows the new name on them" do
    with_settings(two_step_settings(@world, minimum: 500)) do
      Orders::Current.reset
      order_request = submitted_request(@world, lines: [ { description: "Robot kit", price: 600 } ])
      order_request.decide!(:approved, by: @world.mentor)

      ApprovalStep.find_by!(key: "mentor").update!(name: "Coach")
      order_request.reload

      assert_equal [ "mentor" ], order_request.approved_step_keys
      assert_equal "treasurer", order_request.current_step.key
      assert_equal "Coach", order_request.order_approvals.first.step_name
      assert_equal "Coach", order_request.events.where(action: "approved").last.step_name
    end
  end

  test "a retired step's approvals keep its name" do
    with_orders(@world) do
      order_request = approved_request(@world)
      ApprovalStep.find_by!(key: "approval").retire!

      assert_equal "Approval", order_request.order_approvals.first.step_name
    end
  end

  test "approvers are badge holders up to their team, or for every team" do
    with_orders(@world, approval_steps: [ { key: "approval", name: "Approval", minimum: 0,
      approvers: [ [ @world.approver_badge, @world.robotics ], [ @world.funder_badge, nil ] ] } ]) do
      step = Orders::Config.approval_steps.first
      access = ->(person) { Orders::Access.new(person) }

      assert access.(@world.mentor).approver_on?(step, @world.build.id)
      assert_not access.(@world.mentor).approver_on?(step, @world.art.id)
      assert access.(@world.funding_manager).approver_on?(step, @world.art.id)
      assert_not access.(@world.teammate).approver_on?(step, @world.robotics.id)
    end
  end

  test "a badge that admins don't assign never approves" do
    badge = Badge.create!(name: "Self badge", short: "SB", color: "#000000", badge_type: @world.approver_badge.badge_type, permission: :has_account)
    BadgeAssignment.create!(badge: badge, person: @world.teammate)
    with_orders(@world, approval_steps: [ { key: "approval", name: "Approval", minimum: 0, approvers: [ [ badge, nil ] ] } ]) do
      assert_not Orders::Access.new(@world.teammate).approver_on?(Orders::Config.approval_steps.first, @world.robotics.id)
    end
  end

  test "deleting a team removes its approver rows rather than widening them to every team" do
    step = ApprovalStep.create!(name: "Approval")
    approver = step.approvers.create!(badge: @world.approver_badge, team: @world.art)

    @world.art.memberships.delete_all
    @world.art.delete

    assert_not ApprovalStepApprover.exists?(approver.id)
  end

  test "the same badge and team twice is kept once" do
    step = ApprovalStep.create!(name: "Approval", approvers_attributes: [ { badge_id: @world.approver_badge.id, team_id: @world.club.id },
      { badge_id: @world.approver_badge.id, team_id: @world.club.id }, { badge_id: "", team_id: "" } ])

    assert_equal 1, step.approvers.count
  end

  test "steps are never deleted, since approvals point at their key" do
    step = ApprovalStep.create!(name: "Approval")

    assert_not step.removable?
    assert_not step.destroy
    assert ApprovalStep.exists?(step.id)
  end
end
