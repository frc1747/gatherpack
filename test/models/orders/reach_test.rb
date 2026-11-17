require "test_helper"
require "support/orders_world"

class Orders::ReachTest < ActiveSupport::TestCase
  include OrdersWorld

  setup { @world = build_orders_world }

  test "a badge holder reaches the named team and every team below it" do
    reach = Orders::Reach.new([ "#{@world.approver_badge.name} > #{@world.club.name}" ])

    ids = reach.team_ids(@world.mentor)
    assert_includes ids, @world.robotics.id
    assert_includes ids, @world.build.id
    assert_includes ids, @world.club.id
    assert_not_includes ids, @world.art.id
  end

  test "without a team the badge reaches every team" do
    reach = Orders::Reach.new([ @world.approver_badge.name ])

    assert_equal Team.ids.sort, reach.team_ids(@world.mentor).sort
  end

  test "a named team below the holder's leaves their own team out" do
    reach = Orders::Reach.new([ "#{@world.approver_badge.name} > #{@world.build.name}" ])

    assert_equal [ @world.build.id ], reach.team_ids(@world.mentor)
  end

  test "the holder's own teams don't matter" do
    reach = Orders::Reach.new([ "#{@world.approver_badge.name} > #{@world.robotics.name}" ])
    art_holder = orders_person("Painter", teams: [ @world.art ], badges: [ @world.approver_badge ])
    loner = orders_person("Loner", badges: [ @world.approver_badge ])

    [ art_holder, loner ].each do |holder|
      assert_equal [ @world.robotics.id, @world.build.id ].sort, reach.team_ids(holder).sort
    end
  end

  test "a holder in Mentors reaches a team under a sibling Students team" do
    team_type = @world.club.team_type
    program = Team.create!(name: "Program #{SecureRandom.hex(3)}", team_type: team_type)
    mentors = Team.create!(name: "Mentors #{SecureRandom.hex(3)}", team_type: team_type, parent: program)
    students = Team.create!(name: "Students #{SecureRandom.hex(3)}", team_type: team_type, parent: program)
    drivetrain = Team.create!(name: "Drivetrain #{SecureRandom.hex(3)}", team_type: team_type, parent: students)
    holder = orders_person("Coach", teams: [ mentors ], badges: [ @world.approver_badge ])

    assert Orders::Reach.new([ "#{@world.approver_badge.name} > #{program.name}" ]).reaches?(holder, drivetrain)
    assert Orders::Reach.new([ "#{@world.approver_badge.name} > #{students.name}" ]).reaches?(holder, drivetrain)
    assert_not Orders::Reach.new([ "#{@world.approver_badge.name} > #{students.name}" ]).reaches?(holder, mentors)
  end

  test "a named team that isn't found reaches nothing" do
    reach = Orders::Reach.new([ "#{@world.approver_badge.name} > Atlantis" ])

    assert_empty reach.team_ids(@world.mentor)
    assert_not reach.holder?(@world.mentor)
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
