require "test_helper"
require "pstore"
require "tmpdir"

class EventTypeStartsLockedTest < ActiveSupport::TestCase
  setup do
    @saved_store = Settings.instance.store
    @saved_flag = Settings.get(:feature_event_type_starts_locked).instance_variable_get(:@value)
    @settings_dir = Dir.mktmpdir
    Settings.instance.store = PStore.new(File.join(@settings_dir, "settings.pstore"), true)
    Settings[:feature_event_type_starts_locked] = "true"

    @team = Team.create!(name: "Den A", team_type: team_types(:one))
    @locked_type = EventType.create!(name: "Outreach", starts_locked: true)
    @open_type = EventType.create!(name: "Meeting")
  end

  teardown do
    Settings.get(:feature_event_type_starts_locked).instance_variable_set(:@value, @saved_flag)
    Settings.instance.store = @saved_store
    FileUtils.remove_entry(@settings_dir)
  end

  test "a new event of a type that starts locked is locked" do
    assert create_event(@locked_type).locked?
  end

  test "the type locks a new event even when the form left Locked unticked" do
    assert create_event(@locked_type, locked: false).locked?
  end

  test "a new event of another type starts unlocked" do
    assert_not create_event(@open_type).locked?
  end

  test "a manager can unlock one event afterwards" do
    event = create_event(@locked_type)
    event.update!(locked: false)

    assert_not event.reload.locked?
  end

  test "changing an existing event's type leaves its lock alone" do
    event = create_event(@open_type)
    event.update!(event_type: @locked_type)

    assert_not event.reload.locked?
  end

  test "with the feature off, new events start unlocked" do
    Settings[:feature_event_type_starts_locked] = "false"

    assert_not create_event(@locked_type).locked?
  end

  test "a member can't check themselves in to an event of a type that starts locked" do
    member = create_person("member@example.com", manager: false)
    manager = create_person("manager@example.com", manager: true)
    event = create_event(@locked_type)

    assert_not CheckinPolicy.new(member.user, Checkin.new(event: event, person: member)).create?
    assert CheckinPolicy.new(manager.user, Checkin.new(event: event, person: member)).create?
  end

  private

  def create_event(event_type, **attrs)
    Event.create!(name: "Parade", start_time: 1.day.from_now, end_time: 1.day.from_now + 2.hours,
      event_type: event_type, team: @team, **attrs)
  end

  def create_person(email, manager:)
    user = User.create!(email: email, password: "Password1!")
    person = Person.create!(user: user, first_name: email.split("@").first.capitalize, last_name: "Test")
    Membership.create!(person: person, team: @team, manager: manager)
    person
  end
end
