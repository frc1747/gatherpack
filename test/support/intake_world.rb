require_relative "settings_test_helper"

# The fixture world for intake tests:
#
#   Northwind ─┬─ Juniors (needs approval)  ← people apply here
#              ├─ Mentors (needs approval)  ← or here
#              ├─ Volunteers (open to join) ← or here, no approval
#              ├─ Everyone                  ← also added on approval
#              ├─ Class of 2031 / 2032      ← the approver picks one
#              └─ Families                  ← guardians join on approval
#
# The Northwind leader manages Northwind (and so every team below it); the
# Juniors leader manages only Juniors. "Parent of" is a minor guardianship.
module IntakeWorld
  include SettingsTestHelper

  def build_intake_world
    team_type = team_types(:one)
    @northwind = Team.create!(name: "Northwind", team_type: team_type)
    @juniors = Team.create!(name: "Juniors", team_type: team_type, parent: @northwind, join_permission: :requires_approval)
    @mentors = Team.create!(name: "Mentors", team_type: team_type, parent: @northwind, join_permission: :requires_approval)
    @volunteers = Team.create!(name: "Volunteers", team_type: team_type, parent: @northwind, join_permission: :has_account)
    @everyone = Team.create!(name: "Everyone", team_type: team_type, parent: @northwind)
    @class_2031 = Team.create!(name: "Class of 2031", team_type: team_type, parent: @northwind)
    @class_2032 = Team.create!(name: "Class of 2032", team_type: team_type, parent: @northwind)
    @families = Team.create!(name: "Families", team_type: team_type, parent: @northwind)

    @leader = create_intake_person("Lena", "Leader", team: @northwind, manager: true)
    @juniors_leader = create_intake_person("Jun", "Leader", team: @juniors, manager: true)
    @admin = create_intake_person("Ada", "Admin", admin: true)

    @parent_of = RelationshipType.create!(parent_label: "Parent of", child_label: "Child of", permission: :added_by_admin, guardianship: :minor)
    # The leader may give it to anyone in Northwind, and anyone joining may take it.
    @joined_badge = Badge.create!(name: "Joined Online", short: "JO", color: "blue", badge_type: badge_types(:one), team: @northwind,
      permission: "added_by_manager_or_self")

    @registration = Intake::Registration.create!(team: @northwind, title: "Join Northwind", opens_at: 1.day.ago,
      closes_at: 30.days.from_now, created_by: @leader, guardian_relationship_type: @parent_of,
      apply_team_ids: [ @juniors.id, @mentors.id, @volunteers.id ], also_add_team_ids: [ @everyone.id ],
      pick_one_team_ids: [ @class_2031.id, @class_2032.id ], guardian_also_add_team_ids: [ @families.id ],
      badge_ids: [ @joined_badge.id ])
  end

  def create_intake_person(first_name, last_name, team: nil, manager: false, admin: false, email: nil, birthday: nil)
    email ||= "#{first_name}.#{last_name}.#{SecureRandom.hex(3)}@example.com".downcase
    user = User.create!(email: email, password: "Password1!", admin: admin)
    person = Person.create!(user: user, first_name: first_name, last_name: last_name, birthday: birthday)
    Membership.create!(person: person, team: team, manager: manager) if team
    person
  end

  # An entry as the public form makes it, and the token its email would carry.
  def create_intake_entry(first_name: "Riley", last_name: "Rivera", email: "riley@example.com", teams: [ @juniors ], registration: @registration)
    entry = registration.entries.create!(first_name: first_name, last_name: last_name, email: email, facts: { "team_ids" => teams.map(&:id) })
    [ entry, entry.issue_token! ]
  end

  # The feature on, and rate limits counted in memory for the block.
  def with_intake(extra_settings = {}, &block)
    Intake.rate_limit_store = ActiveSupport::Cache::MemoryStore.new
    with_settings({ feature_intake: "true" }.merge(extra_settings), &block)
  ensure
    Intake.rate_limit_store = nil
  end

  def join_params(first_name: "Riley", last_name: "Rivera", email: "riley@example.com", teams: [ @juniors ], started: 10.seconds.ago)
    { entry: { first_name: first_name, last_name: last_name, email: email, team_ids: teams.map(&:id) },
      started: Intake::FormGuard.stamp(started), website: "" }
  end

  # Emails intake sends at once (those carrying a link), as
  # [address, subject, body].
  def capture_intake_mail
    sent = []
    Intake::Notices.sender = ->(_gateway, address, subject, body) { sent << [ address, subject, body ] }
    yield
    sent
  ensure
    Intake::Notices.sender = nil
  end

  # SQL statements run by the block, without schema and transaction noise.
  def sql_statements
    statements = []
    callback = ->(*, payload) { statements << payload[:sql] unless payload[:name].in?([ "SCHEMA", "TRANSACTION" ]) || payload[:cached] }
    ActiveSupport::Notifications.subscribed(callback, "sql.active_record") { yield }
    statements
  end
end
