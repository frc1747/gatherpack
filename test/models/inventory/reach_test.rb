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

  test "team managers reach the teams they manage and those below; admins reach every team" do
    reach = Inventory::Reach.new([])

    assert_equal [ @world.robotics.id, @world.build.id ].sort, reach.team_ids(@world.manager).sort
    assert_equal Team.ids.sort, reach.team_ids(@world.admin).sort
    assert_empty reach.team_ids(@world.member)
  end

  test "badges a member can give themselves don't count" do
    @world.keeper_badge.update_columns(permission: Badge.permissions[:added_by_manager])

    assert_empty Inventory::Reach.new([ "#{@world.keeper_badge.name} > #{@world.club.name}" ]).team_ids(@world.keeper)
  end
end
