# The fixture world for person field access tests (spec section 11.1):
#
#   Org ─ Pack ─┬─ Den A: students A1, A2; Den A leader; Den A assistant
#               └─ Den B: student B1; Den B leader
#   Other Org: an unrelated member
#
# A1's parent and A2's parent are guardians through a "Parent of" type
# (minor guardianship). A1's sibling is related through "Sibling of", which
# grants nothing. The assistant holds a Den A badge, the health officer an
# org-wide badge, and neither is a manager.
module PersonFieldsWorld
  PEOPLE = %i[ a1 a2 b1 parent_a1 parent_a2 sibling_a1 den_a_leader den_b_leader pack_leader assistant health_officer admin outsider ].freeze

  def build_person_fields_world
    @org = create_team("Org")
    @pack = create_team("Pack", parent: @org)
    @den_a = create_team("Den A", parent: @pack)
    @den_b = create_team("Den B", parent: @pack)
    @other_org = create_team("Other Org")

    @people = {}
    @people[:a1] = create_world_person("A1", @den_a)
    @people[:a2] = create_world_person("A2", @den_a)
    @people[:b1] = create_world_person("B1", @den_b)
    @people[:parent_a1] = create_world_person("ParentA1")
    @people[:parent_a2] = create_world_person("ParentA2")
    @people[:sibling_a1] = create_world_person("SiblingA1")
    @people[:den_a_leader] = create_world_person("DenALeader", @den_a, manager: true)
    @people[:den_b_leader] = create_world_person("DenBLeader", @den_b, manager: true)
    @people[:pack_leader] = create_world_person("PackLeader", @pack, manager: true)
    @people[:assistant] = create_world_person("Assistant", @den_a)
    @people[:health_officer] = create_world_person("HealthOfficer")
    @people[:admin] = create_world_person("Admin", admin: true)
    @people[:outsider] = create_world_person("Outsider", @other_org)

    @parent_of = RelationshipType.create!(parent_label: "Parent of", child_label: "Child of", permission: :added_by_admin, guardianship: :minor)
    @sibling_of = RelationshipType.create!(parent_label: "Sibling of", child_label: "Sibling of", permission: :added_by_user, guardianship: :none)
    relate_world(:parent_a1, :a1, @parent_of)
    relate_world(:parent_a2, :a2, @parent_of)
    relate_world(:sibling_a1, :a1, @sibling_of)

    @assistant_badge = create_world_badge("Den A Assistant", team: @den_a)
    @health_officer_badge = create_world_badge("Health Officer")
    BadgeAssignment.create!(badge: @assistant_badge, person: person(:assistant))
    BadgeAssignment.create!(badge: @health_officer_badge, person: person(:health_officer))
  end

  def person(name)
    @people.fetch(name)
  end

  def create_world_field(name, read:, write: "admin", **attributes)
    PersonField.create!(name: name, data_type: :string, read_permission: read, write_permission: write, **attributes)
  end

  private

  def create_team(name, parent: nil)
    Team.create!(name: name, team_type: team_types(:one), parent: parent)
  end

  def create_world_person(name, team = nil, manager: false, admin: false)
    user = User.create!(email: "#{name.downcase}@example.com", password: "Password1!", admin: admin)
    person = Person.create!(user: user, first_name: name, last_name: "World")
    Membership.create!(person: person, team: team, manager: manager) if team
    person
  end

  def relate_world(parent, child, type)
    Relationship.create!(parent: person(parent), child: person(child), relationship_type: type, created_by: person(:admin))
  end

  def create_world_badge(name, team: nil)
    Badge.create!(name: name, short: name.first(3), color: "#336699", badge_type: badge_types(:one), team: team, permission: :added_by_admin)
  end
end
