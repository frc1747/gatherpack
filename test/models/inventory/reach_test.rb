require "test_helper"
require "support/inventory_world"

class Inventory::ReachTest < ActiveSupport::TestCase
  include InventoryWorld

  setup { @world = build_inventory_world }

  test "a badge holder reaches their own team, the teams below and those above up to the cap" do
    ids = Inventory::Reach.new([ "#{@world.keeper_badge.name} > #{@world.club.name}" ]).team_ids(@world.keeper)

    assert_includes ids, @world.robotics.id
    assert_includes ids, @world.build.id
    assert_includes ids, @world.club.id
    assert_not_includes ids, @world.outreach.id
    assert_not_includes ids, @world.art.id
  end

  test "a cap below the club keeps the club out" do
    ids = Inventory::Reach.new([ "#{@world.keeper_badge.name} > #{@world.robotics.name}" ]).team_ids(@world.keeper)

    assert_includes ids, @world.robotics.id
    assert_includes ids, @world.build.id
    assert_not_includes ids, @world.club.id
  end

  test "without a highest team only their own teams and those below" do
    ids = Inventory::Reach.new([ @world.keeper_badge.name ]).team_ids(@world.keeper)

    assert_equal [ @world.robotics.id, @world.build.id ].sort, ids.sort
  end

  test "several pairs give the union" do
    other_badge = Badge.create!(name: "Shop lead #{SecureRandom.hex(3)}", short: "SL", color: "#000000",
      badge_type: @world.keeper_badge.badge_type, permission: :added_by_admin)
    BadgeAssignment.create!(badge: other_badge, person: @world.outreacher)
    BadgeAssignment.create!(badge: other_badge, person: @world.keeper)
    reach = Inventory::Reach.new([ "#{@world.keeper_badge.name} > #{@world.robotics.name}", "#{other_badge.name} > #{@world.club.name}" ])

    assert_includes reach.team_ids(@world.keeper), @world.club.id
    assert_equal [ @world.club.id, @world.outreach.id ].sort, (reach.team_ids(@world.outreacher) & [ @world.club.id, @world.outreach.id, @world.robotics.id ]).sort
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
