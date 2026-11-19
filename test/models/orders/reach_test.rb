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

  test "admins reach everything without a row; managing a team reaches nothing by itself" do
    reach = Orders::Reach.new([])

    assert reach.reaches?(@world.admin, @world.art)
    assert_not reach.reaches?(@world.manager, @world.robotics)
    assert_not reach.reaches?(@world.manager, @world.build)
    assert_not reach.reaches?(@world.requester, @world.robotics)
    assert_not reach.holder?(@world.manager)
  end

  test "a badge that admins don't assign grants nothing" do
    @world.approver_badge.update!(permission: :added_by_admin_or_self)
    reach = Orders::Reach.new([ @world.approver_badge.name ])

    assert_not reach.holder?(@world.mentor)
  end
end

class Orders::ReachRowsTest < ActiveSupport::TestCase
  include OrdersWorld

  # club > robotics > build; the world's manager manages robotics.
  setup do
    @world = build_orders_world
    @club_manager = orders_person("Director", teams: { @world.club => true })
    @build_manager = orders_person("Foreman", teams: { @world.build => true })
  end

  def reach(*lines)
    Orders::Reach.new(lines)
  end

  test "lines read as badge, managers of a team and managers of each team rows" do
    assert_equal [ :badge, "Buyer", "Robotics" ], Orders::Reach.parse_line("Buyer > Robotics")
    assert_equal [ :badge, "Buyer", nil ], Orders::Reach.parse_line("Buyer")
    assert_equal [ :team_managers, "Finance", "Robotics" ], Orders::Reach.parse_line("Managers of Finance > Robotics")
    assert_equal [ :team_managers, "Finance", nil ], Orders::Reach.parse_line("managers of Finance")
    assert_equal [ :own_team_managers, nil, nil ], Orders::Reach.parse_line("Managers of each team")
    assert_nil Orders::Reach.parse_line("  ")
    assert_equal "Managers of Finance > Robotics", Orders::Reach.format_line(:team_managers, "Finance", "Robotics")
    assert_equal "Managers of each team", Orders::Reach.format_line(:own_team_managers, nil, "Robotics")
  end

  test "managers of each team reach the teams they manage and those below, and no others" do
    rows = reach(Orders::Reach::OWN_TEAM_LINE)

    assert_equal [ @world.robotics.id, @world.build.id ].sort, rows.team_ids(@world.manager).sort
    assert_equal [ @world.build.id ], rows.team_ids(@build_manager)
    assert_equal [ @world.club.id, @world.robotics.id, @world.build.id ].sort, rows.team_ids(@club_manager).sort
    assert_empty rows.team_ids(@world.requester)
  end

  test "managers of a team are its own managers only, not those of a team above or below it" do
    rows = reach("Managers of #{@world.robotics.name} > #{@world.art.name}")

    assert_equal [ @world.art.id ], rows.team_ids(@world.manager)
    assert_empty rows.team_ids(@club_manager), "a parent team's manager doesn't count"
    assert_empty rows.team_ids(@build_manager), "a sub-team's manager doesn't count"
    assert_empty rows.team_ids(@world.mentor)
  end

  test "managers of a team with no team reach every team" do
    rows = reach("Managers of #{@world.robotics.name}")

    assert_equal Team.ids.sort, rows.team_ids(@world.manager).sort
    assert_empty rows.team_ids(@build_manager), "a sub-team's manager must not reach every team"
  end

  test "lines that don't read, or name a team or badge that isn't found, grant nothing" do
    rows = reach("Managers of Atlantis", "Managers of #{@world.robotics.name} > Atlantis", "No Such Badge", "> #{@world.art.name}")

    assert_empty rows.rows
    assert_empty rows.team_ids(@world.manager)
    assert_not rows.holder?(@world.manager)
  end

  test "rows add up, and admins reach every team whatever the rows" do
    rows = reach("#{@world.buyer_badge.name} > #{@world.art.name}", Orders::Reach::OWN_TEAM_LINE)
    manager_buyer = orders_person("Lead", teams: { @world.build => true }, badges: [ @world.buyer_badge ])

    assert_equal [ @world.art.id, @world.build.id ].sort, rows.team_ids(manager_buyer).sort
    assert_equal Team.ids.sort, reach.team_ids(@world.admin).sort
  end

  test "an approval step's rows come from its approvers" do
    step = ApprovalStep.create!(name: "Rows #{SecureRandom.hex(2)}", minimum_cents: 0)
    step.approvers.create!(kind: :team_managers, manager_team: @world.club, team: @world.robotics)
    step.approvers.create!(kind: :own_team_managers, team: @world.art)

    assert_equal [ [ :team_managers, @world.club, @world.robotics ], [ :own_team_managers, nil, nil ] ],
      step.reload.reach.rows.map { |row| [ row.kind, row.manager_team, row.team ] }
    assert_equal [ @world.robotics.id, @world.build.id ].sort, step.reach.team_ids(@club_manager).sort - [ @world.club.id ]
    assert_equal [ @world.build.id ], step.reach.team_ids(@build_manager)
    assert_equal [ @world.robotics.id, @world.build.id ].sort, step.reach.team_ids(@world.manager).sort,
      "robotics' manager only through the own-team row: managers of club means club's own managers"
  end
end
