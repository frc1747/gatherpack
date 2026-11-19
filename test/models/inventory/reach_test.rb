require "test_helper"
require "support/inventory_world"

class Inventory::ReachTest < ActiveSupport::TestCase
  include InventoryWorld

  setup { @world = build_inventory_world }

  test "a badge holder reaches the named team and the teams below it" do
    ids = Inventory::Reach.new([ "#{@world.keeper_badge.name} > #{@world.robotics.name}" ]).team_ids(@world.keeper)

    assert_equal [ @world.robotics.id, @world.build.id ].sort, ids.sort
  end

  test "a holder in one branch reaches a sibling branch's team" do
    ids = Inventory::Reach.new([ "#{@world.keeper_badge.name} > #{@world.outreach.name}" ]).team_ids(@world.keeper)

    assert_equal [ @world.outreach.id ], ids
  end

  test "a team above the holder's own reaches the teams below it" do
    ids = Inventory::Reach.new([ "#{@world.keeper_badge.name} > #{@world.club.name}" ]).team_ids(@world.keeper)

    assert_equal [ @world.club, @world.robotics, @world.build, @world.outreach ].map(&:id).sort, ids.sort
    assert_not_includes ids, @world.art.id
  end

  test "without a team the badge reaches every team" do
    ids = Inventory::Reach.new([ @world.keeper_badge.name ]).team_ids(@world.keeper)

    assert_equal Team.ids.sort, ids.sort
  end

  test "a named team that doesn't exist grants nothing" do
    assert_empty Inventory::Reach.new([ "#{@world.keeper_badge.name} > No such team" ]).team_ids(@world.keeper)
  end

  test "several pairs give the union" do
    other_badge = Badge.create!(name: "Shop lead #{SecureRandom.hex(3)}", short: "SL", color: "#000000",
      badge_type: @world.keeper_badge.badge_type, permission: :added_by_admin)
    BadgeAssignment.create!(badge: other_badge, person: @world.outreacher)
    BadgeAssignment.create!(badge: other_badge, person: @world.keeper)
    reach = Inventory::Reach.new([ "#{@world.keeper_badge.name} > #{@world.robotics.name}", "#{other_badge.name} > #{@world.club.name}" ])

    assert_includes reach.team_ids(@world.keeper), @world.club.id
    assert_equal [ @world.club, @world.robotics, @world.build, @world.outreach ].map(&:id).sort, reach.team_ids(@world.outreacher).sort
    assert_equal [ @world.keeper, @world.outreacher ].map(&:id).sort, reach.holders.ids.sort
  end

  test "team managers reach nothing without a row; admins reach every team" do
    reach = Inventory::Reach.new([])

    assert_empty reach.team_ids(@world.manager)
    assert_equal Team.ids.sort, reach.team_ids(@world.admin).sort
    assert_empty reach.team_ids(@world.member)
    assert_empty reach.holders
  end

  test "Managers of each team: a manager reaches the teams they manage and those below" do
    reach = Inventory::Reach.new([ "Managers of each team" ])

    assert_equal [ @world.robotics.id, @world.build.id ].sort, reach.team_ids(@world.manager).sort
    assert_empty reach.team_ids(@world.member)
    assert_empty reach.team_ids(@world.keeper)
    assert_equal [ @world.manager.id ], reach.holders.ids
  end

  test "Managers of a team: only that team's own managers reach the team named or every team" do
    top = inventory_person("Top", teams: { @world.club => true })
    below = inventory_person("Below", teams: { @world.build => true })
    for_art = Inventory::Reach.new([ "Managers of #{@world.robotics.name} > #{@world.art.name}" ])

    assert_equal [ @world.art.id ], for_art.team_ids(@world.manager)
    assert_empty for_art.team_ids(top), "a manager of a team above doesn't count"
    assert_empty for_art.team_ids(below), "a manager of a team below doesn't count"
    assert_empty for_art.team_ids(@world.member)
    assert_equal [ @world.manager.id ], for_art.holders.ids

    assert_equal Team.ids.sort, Inventory::Reach.new([ "managers of #{@world.robotics.name}" ]).team_ids(@world.manager).sort
    assert_empty Inventory::Reach.new([ "Managers of #{@world.outreach.name}" ]).team_ids(@world.manager)
  end

  test "Managers of each team: a manager of a team above reaches the teams below it too" do
    top = inventory_person("Top", teams: { @world.club => true })

    assert_equal [ @world.club, @world.robotics, @world.build, @world.outreach ].map(&:id).sort,
      Inventory::Reach.new([ "Managers of each team" ]).team_ids(top).sort
  end

  test "lines that don't parse or name nothing grant nothing" do
    [ "Managers of No such team", "Managers of #{@world.robotics.name} > No such team",
      "Managers of each team > #{@world.club.name}", "No such badge", " > #{@world.club.name}" ].each do |line|
      reach = Inventory::Reach.new([ line ])
      assert_empty reach.grants, line
      assert_empty reach.team_ids(@world.manager), line
    end
  end

  test "lines parse and format both ways" do
    {
      "Keeper > Club" => [ "badge", "Keeper", nil, "Club" ],
      "Keeper" => [ "badge", "Keeper", nil, nil ],
      "Managers of Finance > Club" => [ "team_managers", nil, "Finance", "Club" ],
      "Managers of Finance" => [ "team_managers", nil, "Finance", nil ],
      "Managers of each team" => [ "own_team_managers", nil, nil, nil ]
    }.each do |text, (kind, badge, manager_team, team)|
      line = Inventory::Reach.parse_line(text)
      assert_equal [ kind, badge, manager_team, team ], [ line.kind, line.badge_name, line.manager_team_name, line.team_name ], text
      assert_equal text, Inventory::Reach.format_line(kind, badge_name: badge, manager_team_name: manager_team, team_name: team)
    end
    assert_nil Inventory::Reach.parse_line("  ")
    assert_nil Inventory::Reach.format_line("badge")
  end

  test "badges a member can give themselves don't count" do
    @world.keeper_badge.update_columns(permission: Badge.permissions[:added_by_manager])

    assert_empty Inventory::Reach.new([ "#{@world.keeper_badge.name} > #{@world.club.name}" ]).team_ids(@world.keeper)
  end
end
