require_relative "settings_test_helper"

# The fixture world for checklist tests:
#
#   Org ─ Club ─┬─ Crew: crew_manager (manager), organizer (organizer badge)
#               ├─ Members: member, member2, kid, rookie
#               └─ Joiners (requires approval): applicant has a pending application
#   Other Org: outsider
#
# club_manager manages Club. parent is the kid's guardian ("Parent of",
# minor guardianship) and on no team. admin is an admin. Safety and Viewer
# are admin-assigned badges; Helper is one Club managers give.
module ChecklistsWorld
  include SettingsTestHelper

  def build_checklists_world
    @org = create_world_team("Org")
    @club = create_world_team("Club", parent: @org)
    @crew = create_world_team("Crew", parent: @club)
    @members = create_world_team("Members", parent: @club)
    @joiners = create_world_team("Joiners", parent: @club, join_permission: :requires_approval)
    @other_org = create_world_team("Other Org")

    @people = {}
    @people[:admin] = create_world_person("Admin", admin: true)
    @people[:club_manager] = create_world_person("ClubManager", @club, manager: true)
    @people[:crew_manager] = create_world_person("CrewManager", @crew, manager: true)
    @people[:organizer] = create_world_person("Organizer", @crew)
    @people[:member] = create_world_person("Member", @members)
    @people[:member2] = create_world_person("MemberTwo", @members)
    @people[:kid] = create_world_person("Kid", @members, birthday: Date.new(2014, 3, 1))
    @people[:rookie] = create_world_person("Rookie", @members)
    @people[:parent] = create_world_person("Parent")
    @people[:applicant] = create_world_person("Applicant")
    @people[:outsider] = create_world_person("Outsider", @other_org)
    MembershipApplication.create!(person: person(:applicant), team: @joiners)

    @parent_of = RelationshipType.create!(parent_label: "Parent of", child_label: "Child of", permission: :added_by_admin, guardianship: :minor)
    Relationship.create!(parent: person(:parent), child: person(:kid), relationship_type: @parent_of, created_by: person(:admin))

    @safety = create_world_badge("Safety 2026")
    @viewer_badge = create_world_badge("Report Viewer")
    @organizer_badge = create_world_badge("Checklist Organizer")
    @helper_badge = Badge.create!(name: "Helper", short: "H", color: "#336699", badge_type: badge_types(:one), team: @club, permission: :added_by_manager)
    BadgeAssignment.create!(badge: @organizer_badge, person: person(:organizer))
  end

  def person(name)
    @people.fetch(name)
  end

  def create_world_checklist(title = "Trip", team: @club, **attributes)
    Checklist.create!({ title: title, team: team, status: :active, starts_on: Date.new(2026, 9, 1), ends_on: Date.new(2027, 6, 30),
      created_by: person(:admin) }.merge(attributes))
  end

  def add_item(checklist, kind, label = kind.to_s.humanize, config = {}, **attributes)
    item = checklist.checklist_items.new({ kind: kind.to_s, label: label }.merge(attributes))
    item.config_params = config
    item.save!
    item
  end

  def add_rule(checklist, effect, target_type, item: nil, **targets)
    checklist.checklist_rules.create!(item: item, effect: effect, target_type: target_type, **targets)
  end

  def give_badge(name, badge)
    BadgeAssignment.create!(person: person(name), badge: badge)
  end

  def refresh(checklist, silent: false)
    Checklists::Refresher.new(checklist.reload, silent: silent).call
  end

  def stored_status(checklist, name, item = nil)
    ChecklistResult.find_by(checklist: checklist, item: item, person: person(name))&.status
  end

  def evaluate(checklist, name, item = nil)
    Checklists::Evaluator.new(checklist.reload).call([ person(name).id ]).dig(person(name).id, item&.id)
  end

  def with_feature(&block)
    with_settings(feature_checklists: "true", &block)
  end

  private

  def create_world_team(name, parent: nil, join_permission: :added_by_manager)
    Team.create!(name: name, team_type: team_types(:one), parent: parent, join_permission: join_permission)
  end

  def create_world_person(name, team = nil, manager: false, admin: false, birthday: nil)
    user = User.create!(email: "#{name.downcase}@example.com", password: "Password1!", admin: admin)
    person = Person.create!(user: user, first_name: name, last_name: "World", birthday: birthday)
    Membership.create!(person: person, team: team, manager: manager) if team
    person
  end

  def create_world_badge(name)
    Badge.create!(name: name, short: name.first(2), color: "#336699", badge_type: badge_types(:one), permission: :added_by_admin)
  end
end
