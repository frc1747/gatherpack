require "test_helper"
require "support/orders_world"

# Requesting, approving, buying and managing funding sources are granted by
# rows; managing a team grants none of them by itself (BL-057).
class Orders::AccessRolesTest < ActiveSupport::TestCase
  include OrdersWorld

  setup { @world = build_orders_world }

  def access(person)
    Orders::Current.reset
    Orders::Access.for(person)
  end

  def no_manager_rows
    { approval_steps: [ { key: "approval", name: "Approval", minimum: 0, approvers: [ [ @world.approver_badge, @world.club ] ] } ],
      orders_buyers: "#{@world.buyer_badge.name} > #{@world.club.name}",
      orders_funding_managers: "#{@world.funder_badge.name} > #{@world.club.name}" }
  end

  test "a manager without a row can't approve, buy or manage funding sources" do
    with_orders(@world, **no_manager_rows) do
      order_request = submitted_request(@world)
      manager = access(@world.manager)

      assert_not manager.approver?
      assert_not manager.buyer?
      assert_not manager.funding_manager?
      assert_not order_request.can_decide?(@world.manager)
      assert access(@world.mentor).approver_on?(Orders::Config.approval_steps.first, @world.robotics.id)
    end
  end

  test "with managers of each team, a manager approves and buys for their team and the teams below" do
    with_orders(@world) do
      manager = access(@world.manager)
      step = Orders::Config.approval_steps.first

      [ @world.robotics, @world.build ].each do |team|
        assert manager.approver_on?(step, team.id)
        assert manager.buyer_for?(team.id)
        assert manager.funding_manager_for?(team.id)
      end
      assert_not manager.approver_on?(step, @world.club.id)
      assert_not manager.buyer_for?(@world.art.id)
      assert submitted_request(@world).can_decide?(@world.manager)
    end
  end

  test "managers of a team for every team buy for every team" do
    with_orders(@world, orders_buyers: "Managers of #{@world.robotics.name}") do
      assert access(@world.manager).buyer_for?(@world.art.id)
      assert_not access(@world.buyer).buyer?
    end
  end

  test "a manager still can't approve their own request" do
    with_orders(@world) do
      order_request = submitted_request(@world, by: @world.manager)

      assert_not order_request.can_decide?(@world.manager)
      assert order_request.can_decide?(@world.mentor)
    end
  end

  test "with no approval step, admins and the managers of each team approve" do
    with_orders(@world, approval_steps: []) do
      step = Orders::Config.approval_steps.first

      assert_equal [ :own_team_managers ], step.reach.rows.map(&:kind)
      assert access(@world.manager).approver_on?(step, @world.robotics.id)
      assert_not access(@world.mentor).approver?
      assert access(@world.admin).approver_on?(step, @world.art.id)
    end
  end

  test "who can ask: team members, and holders of a badge or managers row for the teams it reaches" do
    with_orders(@world, orders_requesters: "#{@world.art.name}\n#{@world.buyer_badge.name} > #{@world.robotics.name}\nManagers of #{@world.robotics.name}") do
      assert access(@world.outsider).requester?
      assert access(@world.buyer).requester?
      assert access(@world.buyer).may_request_for?(@world.build.id)
      assert access(@world.manager).requester?
      assert_not access(@world.teammate).requester?
      assert_not access(@world.builder).requester?
    end
  end

  test "blank who can ask still means everyone signed in" do
    with_orders(@world, orders_requesters: "") do
      assert access(@world.teammate).requester?
    end
  end
end
