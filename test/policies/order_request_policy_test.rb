require "test_helper"
require "support/orders_world"

class OrderRequestPolicyTest < ActiveSupport::TestCase
  include OrdersWorld

  setup { @world = build_orders_world }

  def policy(person, record)
    Orders::Current.reset
    OrderRequestPolicy.new(person.user, record)
  end

  def visible(person)
    Orders::Current.reset
    OrderRequestPolicy::Scope.new(person.user, OrderRequest).resolve.to_a
  end

  test "who sees a request" do
    with_orders(@world) do
      order_request = submitted_request(@world)
      order_request.follow!(@world.outsider)

      %i[requester mentor teammate manager buyer admin outsider builder].each do |who|
        expected = who != :builder
        assert_equal expected, policy(@world[who], order_request).show?, "#{who} show?"
        assert_equal expected, visible(@world[who]).include?(order_request), "#{who} in scope"
      end
    end
  end

  test "team members don't see the team's requests when orders_team_can_see is off" do
    with_orders(@world, orders_team_can_see: "false") do
      order_request = submitted_request(@world)

      assert_not policy(@world.teammate, order_request).show?
      assert_not_includes visible(@world.teammate), order_request
      assert policy(@world.mentor, order_request).show?
    end
  end

  test "a draft is its requester's alone" do
    with_orders(@world) do
      draft = draft_request(@world)

      assert policy(@world.requester, draft).show?
      assert policy(@world.requester, draft).destroy?
      assert_not policy(@world.manager, draft).show?
      assert_not policy(@world.teammate, draft).show?
      assert_equal [ draft ], visible(@world.requester)
      assert_empty visible(@world.manager)
    end
  end

  test "the requester edits while it's editable, and managers until it's finished" do
    with_orders(@world) do
      order_request = submitted_request(@world)
      assert policy(@world.requester, order_request).update?
      assert_not policy(@world.teammate, order_request).update?

      order_request.decide!(:approved, by: @world.mentor)
      order_request.reload
      assert_not policy(@world.requester, order_request).update?
      assert policy(@world.manager, order_request).update?
      assert_not policy(@world.requester, order_request).destroy?
    end
  end

  test "adding and listing items follow the request" do
    with_orders(@world) do
      order_request = submitted_request(@world)
      line = order_request.order_lines.build

      Orders::Current.reset
      assert_not OrderLinePolicy.new(@world.outsider.user, line).create?
      assert_not OrderLinePolicy.new(@world.outsider.user, line).index?
      assert_not OrderLinePolicy.new(@world.teammate.user, line).create?
      assert OrderLinePolicy.new(@world.teammate.user, line).index?
      assert OrderLinePolicy.new(@world.requester.user, line).create?
      assert OrderLinePolicy.new(@world.mentor.user, line).create?, "an approver deciding it"

      order_request.decide!(:approved, by: @world.mentor)
      approved_line = order_request.reload.order_lines.build
      Orders::Current.reset
      assert_not OrderLinePolicy.new(@world.requester.user, approved_line).create?
    end
  end

  test "deciding follows the approval engine" do
    with_orders(@world) do
      order_request = submitted_request(@world)

      assert policy(@world.mentor, order_request).decide?
      assert policy(@world.mentor, order_request).approver_edit?
      assert_not policy(@world.requester, order_request).decide?
      assert_not policy(@world.parent, order_request).decide?
      assert_not policy(@world.buyer, order_request).decide?
    end
  end

  test "buyers buy within reach; requesters and team members receive" do
    with_orders(@world) do
      order_request = approved_request(@world)
      art_request = approved_request(@world, by: @world.outsider, team: @world.art)

      assert policy(@world.buyer, order_request).buy?
      assert_not policy(@world.buyer, art_request).buy?
      assert policy(@world.manager, order_request).buy?
      assert_not policy(@world.requester, order_request).buy?

      %i[requester teammate buyer manager].each { |who| assert policy(@world[who], order_request).receive?, who }
      assert_not policy(@world.outsider, order_request).receive?
    end
  end

  test "requesters see the funding source only when they may pick it" do
    with_orders(@world) do
      order_request = submitted_request(@world)
      assert_not policy(@world.requester, order_request).see_funding?
      assert_not policy(@world.requester, order_request).set_funding?
      assert policy(@world.mentor, order_request).see_funding?
      assert policy(@world.mentor, order_request).set_funding?
    end
    with_orders(@world, orders_requesters_pick_funding: "true") do
      order_request = submitted_request(@world)
      assert policy(@world.requester, order_request).see_funding?
      assert policy(@world.requester, order_request).set_funding?
    end
  end

  test "only people in orders_requesters may create a request" do
    with_orders(@world, orders_requesters: @world.robotics.name) do
      assert policy(@world.requester, OrderRequest).create?
      assert policy(@world.builder, OrderRequest).create?, "members of teams below count"
      assert_not policy(@world.outsider, OrderRequest).create?
    end
    with_orders(@world) do
      assert policy(@world.outsider, OrderRequest).create?
    end
  end

  test "members of an orders_viewers team and the teams below see every request, read only" do
    with_orders(@world, orders_viewers: @world.robotics.name) do
      order_request = approved_request(@world, by: @world.outsider, team: @world.art)

      # builder is on build, below robotics; nothing else lets them see art's requests.
      viewer = policy(@world.builder, order_request)
      assert viewer.show?
      assert_includes visible(@world.builder), order_request
      assert viewer.comment?
      %i[update? cancel? close? follow? add_watchers? decide? approver_edit? set_funding? buy? receive? see_funding?].each do |action|
        assert_not viewer.public_send(action), "viewer #{action}"
      end
      assert_not OrderLinePolicy.new(@world.builder.user, order_request.order_lines.first).buy?

      club_member = orders_person("Clubber", teams: [ @world.club ])
      assert_not policy(club_member, order_request).show?, "a team above a listed one doesn't count"
      assert_not_includes visible(club_member), order_request
    end
  end

  test "orders_viewers don't see drafts" do
    with_orders(@world, orders_viewers: @world.robotics.name) do
      draft = draft_request(@world, by: @world.outsider, team: @world.art)

      assert_not policy(@world.builder, draft).show?
      assert_not_includes visible(@world.builder), draft
    end
  end

  test "orders_viewers comment only when team members can" do
    with_orders(@world, orders_viewers: @world.robotics.name, orders_team_can_see: "false") do
      order_request = submitted_request(@world, by: @world.outsider, team: @world.art)

      assert policy(@world.builder, order_request).show?
      assert_not policy(@world.builder, order_request).comment?
    end
  end

  test "nobody sees every request while orders_viewers is blank" do
    with_orders(@world) do
      order_request = submitted_request(@world, by: @world.outsider, team: @world.art)

      assert_not policy(@world.builder, order_request).show?
      assert_not_includes visible(@world.builder), order_request
    end
  end

  test "an approver in Mentors decides a request from a team under a sibling Students team" do
    team_type = @world.club.team_type
    program = Team.create!(name: "Program #{SecureRandom.hex(3)}", team_type: team_type)
    mentors = Team.create!(name: "Mentors #{SecureRandom.hex(3)}", team_type: team_type, parent: program)
    students = Team.create!(name: "Students #{SecureRandom.hex(3)}", team_type: team_type, parent: program)
    drivetrain = Team.create!(name: "Drivetrain #{SecureRandom.hex(3)}", team_type: team_type, parent: students)
    coach = orders_person("Coach", teams: [ mentors ], badges: [ @world.approver_badge ])
    student = orders_person("Student", teams: [ drivetrain ])

    with_orders(@world, approval_steps: [ { key: "approval", name: "Approval", minimum: 0,
      approvers: [ [ @world.approver_badge, program ] ] } ]) do
      order_request = submitted_request(@world, by: student, team: drivetrain)

      assert policy(coach, order_request).show?
      assert_includes visible(coach), order_request
      assert policy(coach, order_request).decide?
    end
  end
end
