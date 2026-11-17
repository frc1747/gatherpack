require_relative "settings_test_helper"

# The fixture world for commitment tests:
#
#   Org ─ Club ─┬─ Crew: organizer (organizer badge), crew_manager
#               └─ Members: member, member2, kid
#   Other Org: outsider
#
# organizer is "Parent of" kid. admin is an admin. The organizer badge is
# admin-assigned. Outreach and Meeting are event types; the commitment runs
# through October 2026, owed by Members, counted in shifts.
module CommitmentsWorld
  include SettingsTestHelper

  def build_commitments_world
    @org = create_world_team("Org")
    @club = create_world_team("Club", parent: @org)
    @crew = create_world_team("Crew", parent: @club)
    @members = create_world_team("Members", parent: @club)
    @other_org = create_world_team("Other Org")

    @people = {}
    @people[:admin] = create_world_person("Admin", admin: true)
    @people[:organizer] = create_world_person("Organizer", @crew)
    @people[:crew_manager] = create_world_person("CrewManager", @crew, manager: true)
    @people[:member] = create_world_person("Member", @members)
    @people[:member2] = create_world_person("MemberTwo", @members)
    @people[:kid] = create_world_person("Kid", @members)
    @people[:outsider] = create_world_person("Outsider", @other_org)

    @parent_of = RelationshipType.create!(parent_label: "Parent of", child_label: "Child of", permission: :added_by_admin)
    Relationship.create!(parent: person(:organizer), child: person(:kid), relationship_type: @parent_of, created_by: person(:admin))

    @organizer_badge = Badge.create!(name: "Commitment Organizer", short: "CO", color: "#336699", badge_type: badge_types(:one), permission: :added_by_admin)
    BadgeAssignment.create!(badge: @organizer_badge, person: person(:organizer))

    @outreach = EventType.create!(name: "Outreach")
    @meeting = EventType.create!(name: "Meeting")
  end

  def person(name)
    @people.fetch(name)
  end

  def create_world_commitment(title = "Shifts", team: @club, owing_team: @members, **attributes)
    Commitment.create!({ title: title, team: team, owing_team: owing_team, base_amount: 2, unit: "shifts",
      starts_on: Date.new(2026, 10, 1), ends_on: Date.new(2026, 10, 31) }.merge(attributes))
  end

  def create_world_event(name, start_time, event_type: @outreach, team: @club)
    start_time = Time.zone.parse(start_time) if start_time.is_a?(String)
    Event.create!(name: name, start_time: start_time, end_time: start_time + 2.hours, event_type: event_type, team: team)
  end

  def check_in(name, event)
    Checkin.create!(person: person(name), event: event)
  end

  def with_feature(&block)
    with_settings(feature_commitments: "true", &block)
  end

  def with_organizer_grants(text, &block)
    with_settings(commitments_organizers: text, &block)
  end

  def with_feature_and_grants(text = "Commitment Organizer > Club", &block)
    with_settings(feature_commitments: "true", commitments_organizers: text, &block)
  end

  private

  def create_world_team(name, parent: nil)
    Team.create!(name: name, team_type: team_types(:one), parent: parent)
  end

  def create_world_person(name, team = nil, manager: false, admin: false)
    user = User.create!(email: "#{name.downcase}@example.com", password: "Password1!", admin: admin)
    person = Person.create!(user: user, first_name: name, last_name: "World")
    Membership.create!(person: person, team: team, manager: manager) if team
    person
  end
end
