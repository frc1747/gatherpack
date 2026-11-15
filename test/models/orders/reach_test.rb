require "test_helper"
require "support/orders_world"

class Orders::ReachTest < ActiveSupport::TestCase
  include OrdersWorld

  setup { @world = build_orders_world }

  test "a badge holder reaches their own team, the teams below and those above up to the cap" do
    reach = Orders::Reach.new([ "#{@world.approver_badge.name} > #{@world.club.name}" ])

    ids = reach.team_ids(@world.mentor)
    assert_includes ids, @world.robotics.id
    assert_includes ids, @world.build.id
    assert_includes ids, @world.club.id
    assert_not_includes ids, @world.art.id
  end

  test "without a highest team only their own teams and those below" do
    reach = Orders::Reach.new([ @world.approver_badge.name ])

    ids = reach.team_ids(@world.mentor)
    assert_includes ids, @world.robotics.id
    assert_includes ids, @world.build.id
    assert_not_includes ids, @world.club.id
  end

  test "a cap below the holder's team leaves their own team out" do
    reach = Orders::Reach.new([ "#{@world.approver_badge.name} > #{@world.build.name}" ])

    assert_equal [ @world.build.id ], reach.team_ids(@world.mentor)
  end

  test "admins reach everything and managers their teams, without a badge" do
    reach = Orders::Reach.new([])

    assert reach.reaches?(@world.admin, @world.art)
    assert reach.reaches?(@world.manager, @world.build)
    assert_not reach.reaches?(@world.manager, @world.art)
    assert_not reach.reaches?(@world.requester, @world.robotics)
  end

  test "a badge that admins don't assign grants nothing" do
    @world.approver_badge.update!(permission: :added_by_admin_or_self)
    reach = Orders::Reach.new([ @world.approver_badge.name ])

    assert_not reach.holder?(@world.mentor)
  end
end
