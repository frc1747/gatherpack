require "support/settings_test_helper"

# Builds people, teams and grants for orders tests without fixtures:
#
#   club (parent)
#   └── robotics          requester, mentor (approver badge), teammate
#       └── build         builder
#   art                   outsider
#
# Plus an admin, a manager of robotics, a buyer and a funding manager
# (badge grants), a parent (relative of the requester) and two vendors.
module OrdersWorld
  include SettingsTestHelper

  World = Struct.new(:club, :robotics, :build, :art, :admin, :manager, :requester, :mentor, :teammate,
    :builder, :outsider, :buyer, :funding_manager, :parent, :approver_badge, :buyer_badge,
    :funder_badge, :preferred_vendor, :other_vendor, keyword_init: true)

  def build_orders_world
    team_type = TeamType.first || TeamType.create!(name: "Group")
    club = Team.create!(name: "Club #{SecureRandom.hex(3)}", team_type: team_type)
    robotics = Team.create!(name: "Robotics #{SecureRandom.hex(3)}", team_type: team_type, parent: club)
    build = Team.create!(name: "Build #{SecureRandom.hex(3)}", team_type: team_type, parent: robotics)
    art = Team.create!(name: "Art #{SecureRandom.hex(3)}", team_type: team_type)
    badge_type = BadgeType.first || BadgeType.create!(name: "Role")

    approver_badge = Badge.create!(name: "Approver #{SecureRandom.hex(3)}", short: "AP", color: "#000000", badge_type: badge_type, permission: :added_by_admin)
    buyer_badge = Badge.create!(name: "Buyer #{SecureRandom.hex(3)}", short: "BY", color: "#000000", badge_type: badge_type, permission: :added_by_admin)
    funder_badge = Badge.create!(name: "Funder #{SecureRandom.hex(3)}", short: "FM", color: "#000000", badge_type: badge_type, permission: :added_by_admin)

    world = World.new(
      club: club, robotics: robotics, build: build, art: art,
      admin: orders_person("Admin", admin: true),
      manager: orders_person("Manager", teams: { robotics => true }),
      requester: orders_person("Requester", teams: [ robotics ]),
      mentor: orders_person("Mentor", teams: [ robotics ], badges: [ approver_badge ]),
      teammate: orders_person("Teammate", teams: [ robotics ]),
      builder: orders_person("Builder", teams: [ build ]),
      outsider: orders_person("Outsider", teams: [ art ]),
      buyer: orders_person("Buyer", teams: [ robotics ], badges: [ buyer_badge ]),
      funding_manager: orders_person("Funder", teams: [ robotics ], badges: [ funder_badge ]),
      parent: orders_person("Parent", teams: [ robotics ], badges: [ approver_badge ]),
      approver_badge: approver_badge, buyer_badge: buyer_badge, funder_badge: funder_badge,
      preferred_vendor: Vendor.create!(name: "Parts Depot", domains: [ "partsdepot.example" ], preferred: true,
        part_number_pattern: "/p/([A-Z0-9-]+)"),
      other_vendor: Vendor.create!(name: "Hardware Barn", domains: [ "hardwarebarn.example" ])
    )
    relate(world.parent, world.requester)
    world
  end

  # Settings that turn orders on and give the world's badges their grants.
  def orders_settings(world, **overrides)
    {
      feature_orders: "true",
      orders_approval_steps: JSON.generate([ { "key" => "approval", "name" => "Approval", "minimum" => 0,
        "approvers" => [ "#{world.approver_badge.name} > #{world.club.name}" ] } ]),
      orders_buyers: "#{world.buyer_badge.name} > #{world.club.name}",
      orders_funding_managers: "#{world.funder_badge.name} > #{world.club.name}"
    }.merge(overrides)
  end

  def two_step_settings(world, minimum: 500)
    orders_settings(world, orders_approval_steps: JSON.generate([
      { "key" => "mentor", "name" => "Mentor", "minimum" => 0, "approvers" => [ "#{world.approver_badge.name} > #{world.club.name}" ] },
      { "key" => "treasurer", "name" => "Treasurer", "minimum" => minimum, "approvers" => [] }
    ]))
  end

  def with_orders(world, **overrides, &block)
    with_settings(orders_settings(world, **overrides)) do
      Orders::Current.reset
      block.call
    ensure
      Orders::Current.reset
    end
  end

  def orders_person(name, admin: false, teams: [], badges: [])
    user = User.create!(email: "#{name.downcase}-#{SecureRandom.hex(4)}@example.com", password: "password123", admin: admin)
    person = Person.create!(first_name: name, last_name: "Example", display_name: "#{name} Example", user: user)
    Array(teams).each do |team, manager|
      Membership.create!(person: person, team: team, manager: manager || false)
    end
    badges.each { |badge| BadgeAssignment.create!(badge: badge, person: person) }
    person
  end

  def relate(parent, child)
    type = RelationshipType.first || RelationshipType.create!(parent_label: "Parent", child_label: "Child", permission: :added_by_admin)
    Relationship.new(relationship_type: type, parent: parent, child: child).save!(validate: false)
  end

  # A submitted request from the world's requester with the given lines
  # (OrderLine attributes; a price in dollars as :price).
  def submitted_request(world, lines: [ { description: "Gear", price: 10 } ], by: world.requester, team: world.robotics, **attributes)
    order_request = draft_request(world, lines: lines, by: by, team: team, **attributes)
    order_request.submit!(by: by)
    order_request.reload
  end

  def draft_request(world, lines: [ { description: "Gear", price: 10 } ], by: world.requester, team: world.robotics, **attributes)
    OrderRequest.draft_for(person: by, team: team, lines: lines.map { |line| line_attributes(line) }, **attributes)
  end

  def approved_request(world, lines: [ { description: "Gear", price: 10 } ], approver: nil, **attributes)
    order_request = submitted_request(world, lines: lines, **attributes)
    approver ||= order_request.team_id == world.art.id ? world.admin : world.mentor
    order_request.decide!(:approved, by: approver)
    order_request.reload
  end

  def line_attributes(line)
    line = line.dup
    price = line.delete(:price)
    line[:estimated_unit_price_cents] = (price * 100).round if price
    line
  end

  def buy(world, lines, vendor: nil, prices: {}, **attributes)
    Orders::RecordPurchase.new(buyer: world.buyer, lines: lines, vendor: vendor, other_vendor_name: vendor ? nil : "Corner Store",
      prices: prices, attributes: { ordered_on: Date.current }.merge(attributes)).call
  end
end
