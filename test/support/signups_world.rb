# The fixture world for sign-up sheet tests:
#
#   Org ─ Club ─┬─ Concessions: worker (organizer badge), Concessions manager
#               └─ Students: student, student2
#   Other Org: outsider
#
# parent is "Parent of" student and in no team; sibling is "Sibling of"
# student. admin is an admin. The organizer badge is admin-assigned; the
# license badge is held by worker. The sheet belongs to Club and has one
# event, Game Day, on Oct 24.
module SignupsWorld
  def build_signups_world
    @org = create_world_team("Org")
    @club = create_world_team("Club", parent: @org)
    @concessions = create_world_team("Concessions", parent: @club)
    @students = create_world_team("Students", parent: @club)
    @other_org = create_world_team("Other Org")

    @people = {}
    @people[:admin] = create_world_person("Admin", admin: true)
    @people[:worker] = create_world_person("Worker", @concessions, birthday: Date.new(1990, 3, 1))
    @people[:concessions_manager] = create_world_person("ConcessionsManager", @concessions, manager: true)
    @people[:student] = create_world_person("Student", @students, birthday: Date.new(2010, 10, 25))
    @people[:student2] = create_world_person("StudentTwo", @students)
    @people[:parent] = create_world_person("Parent")
    @people[:sibling] = create_world_person("Sibling")
    @people[:outsider] = create_world_person("Outsider", @other_org)

    @parent_of = RelationshipType.create!(parent_label: "Parent of", child_label: "Child of", permission: :added_by_admin)
    @sibling_of = RelationshipType.create!(parent_label: "Sibling of", child_label: "Sibling of", permission: :added_by_admin)
    relate(:parent, :student, @parent_of)
    relate(:sibling, :student, @sibling_of)

    @organizer_badge = create_world_badge("Sheet Organizer")
    @license_badge = create_world_badge("Alcohol License")
    BadgeAssignment.create!(badge: @organizer_badge, person: person(:worker))
    BadgeAssignment.create!(badge: @license_badge, person: person(:worker))

    @event = create_world_event("Game Day", Time.zone.parse("2026-10-24 10:00"))
  end

  def person(name)
    @people.fetch(name)
  end

  def create_world_sheet(title = "Snack Stand", team: @club, events: [ @event ], status: :open, **attributes)
    sheet = SignupSheet.create!(title: title, team: team, status: status, **attributes)
    events.each { |event| sheet.signup_sheet_events.create!(event: event) }
    sheet
  end

  def create_world_event(name, start_time, team: @club)
    Event.create!(name: name, start_time: start_time, end_time: start_time + 4.hours, event_type: event_types(:one), team: team)
  end

  def slot_for(position, event = @event)
    position.signup_slots.find_by!(event: event)
  end

  # Sets Settings values for the duration of a block. Writes go to a
  # throwaway PStore so tests never touch storage/settings.pstore, and the
  # previous values are restored afterwards.
  def with_settings(values)
    restore = apply_settings(values)
    yield
  ensure
    restore&.call
  end

  # Sets Settings values until the returned proc is called, for setups that
  # need them through the whole test (call it in teardown).
  def apply_settings(values)
    settings = Settings.instance
    original_store = settings.store
    settings.store = PStore.new(Rails.root.join("tmp", "test-settings-#{Process.pid}.pstore").to_s)
    previous = values.keys.to_h { |key| [ key, Settings.get(key).instance_variable_get(:@value) ] }
    values.each { |key, value| Settings[key] = value }
    lambda do
      previous.each { |key, value| Settings[key] = value }
      settings.store = original_store
    end
  end

  def with_organizer_grants(text, &block)
    with_settings(signups_organizers: text, &block)
  end

  # The emails enqueued through SendEmailJob, as [address, subject, body].
  # Needs ActiveJob::TestHelper.
  def enqueued_emails
    enqueued_jobs.select { |job| job[:job] == SendEmailJob }.map { |job| job[:args][1..3] }
  end

  def enqueued_email_addresses
    enqueued_emails.map(&:first).sort
  end

  def email_of(name)
    person(name).user.email
  end

  # Places a sign-up as its organizer would, skipping the checks, for setups.
  def create_world_signup(position, name, event: @event, status: :active, **attributes)
    attributes[:quantity] ||= 1 if position.items?
    Signup.create!(signup_slot: slot_for(position, event), person: person(name), signed_up_by: person(name), status: status, **attributes)
  end

  private

  def create_world_team(name, parent: nil)
    Team.create!(name: name, team_type: team_types(:one), parent: parent)
  end

  def create_world_person(name, team = nil, manager: false, admin: false, birthday: nil)
    user = User.create!(email: "#{name.downcase}@example.com", password: "Password1!", admin: admin)
    person = Person.create!(user: user, first_name: name, last_name: "World", birthday: birthday)
    Membership.create!(person: person, team: team, manager: manager) if team
    person
  end

  def relate(parent, child, type)
    Relationship.create!(parent: person(parent), child: person(child), relationship_type: type, created_by: person(:admin))
  end

  def create_world_badge(name, team: nil)
    Badge.create!(name: name, short: name.first(3), color: "#336699", badge_type: badge_types(:one), team: team, permission: :added_by_admin)
  end
end
