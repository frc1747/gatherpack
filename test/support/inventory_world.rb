require "support/settings_test_helper"

# Builds people, teams, places and an item for inventory tests without
# fixtures:
#
#   club (top level)      shop › cabinet (A) › bin1 (A-1), bin2 (A-2)
#   ├── robotics          member, teammate, keeper (inventory badge), manager
#   │   └── build         builder
#   └── outreach          outreacher
#   art (top level)       outsider
#
# Plus an admin, a robot (a machine owned by robotics) and screws (a club
# item kept in bin1, order more at 10).
module InventoryWorld
  include SettingsTestHelper

  # Hooks created by #record_hooks append [event, record id] here.
  HOOK_LOG = []

  World = Struct.new(:club, :robotics, :build, :outreach, :art, :admin, :manager, :member, :teammate, :keeper,
    :builder, :outreacher, :outsider, :keeper_badge, :shop, :cabinet, :bin1, :bin2, :robot, :screws, keyword_init: true)

  def build_inventory_world
    team_type = TeamType.first || TeamType.create!(name: "Group")
    club = Team.create!(name: "Club #{SecureRandom.hex(3)}", team_type: team_type)
    robotics = Team.create!(name: "Robotics #{SecureRandom.hex(3)}", team_type: team_type, parent: club)
    build = Team.create!(name: "Build #{SecureRandom.hex(3)}", team_type: team_type, parent: robotics)
    outreach = Team.create!(name: "Outreach #{SecureRandom.hex(3)}", team_type: team_type, parent: club)
    art = Team.create!(name: "Art #{SecureRandom.hex(3)}", team_type: team_type)
    badge_type = BadgeType.first || BadgeType.create!(name: "Role")
    keeper_badge = Badge.create!(name: "Keeper #{SecureRandom.hex(3)}", short: "KP", color: "#000000", badge_type: badge_type,
      permission: :added_by_admin)

    shop = Location.create!(team: club, name: "Shop")
    cabinet = Location.create!(parent: shop, name: "Cabinet", code: "A")
    World.new(
      club: club, robotics: robotics, build: build, outreach: outreach, art: art,
      admin: inventory_person("Admin", admin: true),
      manager: inventory_person("Manager", teams: { robotics => true }),
      member: inventory_person("Member", teams: [ robotics ]),
      teammate: inventory_person("Teammate", teams: [ robotics ]),
      keeper: inventory_person("Keeper", teams: [ robotics ], badges: [ keeper_badge ]),
      builder: inventory_person("Builder", teams: [ build ]),
      outreacher: inventory_person("Outreacher", teams: [ outreach ]),
      outsider: inventory_person("Outsider", teams: [ art ]),
      keeper_badge: keeper_badge,
      shop: shop, cabinet: cabinet,
      bin1: Location.create!(parent: cabinet, name: "Bin 1", code: "A-1"),
      bin2: Location.create!(parent: cabinet, name: "Bin 2", code: "A-2"),
      robot: Location.create!(team: robotics, name: "Robot", kind: "machine"),
      screws: nil
    ).tap do |world|
      world.screws = Item.create!(team: club, name: "M4 screw", manufacturer_part_number: "M4-12", category: "Fasteners",
        home_location: world.bin1, reorder_point: 10)
    end
  end

  # Settings that turn inventory on and give the keeper badge its grant,
  # capped at the club.
  def inventory_settings(world, **overrides)
    { feature_inventory: "true", inventory_managers: "#{world.keeper_badge.name} > #{world.club.name}" }.merge(overrides)
  end

  def with_inventory(world, **overrides, &block)
    with_settings(inventory_settings(world, **overrides)) do
      Inventory::Current.reset
      block.call
    ensure
      Inventory::Current.reset
    end
  end

  # Records a movement as the admin unless someone else is given.
  def record(world, kind, quantity = nil, item: world.screws, location: world.bin1, person: world.admin, **options)
    StockMovement.record!(kind: kind, item: item, location: location, quantity: quantity, person: person, **options)
  end

  # Starting stock, recorded as an admin's added movement.
  def stock!(world, quantity, item: world.screws, location: world.bin1)
    record(world, :added, quantity, item: item, location: location, reason: "Starting count")
  end

  # A tracked item kept in bin1 with units there (codes U-1, U-2 ...).
  def tracked_item!(world, name: "Motor", units: 0, reorder_point: nil, team: world.club, readings: [])
    item = Item.create!(team: team, name: name, tracked: true, home_location: world.bin1, reorder_point: reorder_point,
      reading_fields: readings)
    units.times.map { |index| ItemUnit.create_with_event!(item: item, location: world.bin1, person: world.admin).tap { |unit| unit.update!(code: "#{name[0, 3].upcase}-#{index + 1}") } }
    item
  end

  # A hook for each event that logs [event, record id] to HOOK_LOG.
  def record_hooks(*events)
    HOOK_LOG.clear
    events.each { |event| Hook.create!(name: event, event: event, code: "InventoryWorld::HOOK_LOG << [ #{event.inspect}, model.id ]") }
  end

  def hook_log
    HOOK_LOG
  end

  def inventory_person(name, admin: false, teams: [], badges: [])
    user = User.create!(email: "#{name.downcase}-#{SecureRandom.hex(4)}@example.com", password: "password123", admin: admin)
    person = Person.create!(first_name: name, last_name: "Example", display_name: "#{name} Example", user: user)
    Array(teams).each do |team, manager|
      Membership.create!(person: person, team: team, manager: manager || false)
    end
    badges.each { |badge| BadgeAssignment.create!(badge: badge, person: person) }
    person
  end
end
