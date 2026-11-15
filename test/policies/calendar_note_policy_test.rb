require "test_helper"

class CalendarNotePolicyTest < ActiveSupport::TestCase
  setup do
    # Robotics (run by @manager, @member on it)
    # └── Robotics Jr (@junior on it)
    # Drama (@outsider on it)
    @robotics = Team.create!(name: "Robotics", team_type: team_types(:one))
    @robotics_jr = Team.create!(name: "Robotics Jr", team_type: team_types(:one), parent: @robotics)
    @drama = Team.create!(name: "Drama", team_type: team_types(:one))

    @admin = create_person("admin", admin: true)
    @manager = create_person("manager")
    Membership.create!(person: @manager, team: @robotics, manager: true)
    @member = create_person("member")
    Membership.create!(person: @member, team: @robotics)
    @junior = create_person("junior")
    Membership.create!(person: @junior, team: @robotics_jr)
    @outsider = create_person("outsider")
    Membership.create!(person: @outsider, team: @drama)
  end

  def test_scope
    note = CalendarNote.create!(name: "Drama rehearsal", start_time: 1.day.from_now, noteable: @drama)

    assert_includes CalendarNotePolicy::Scope.new(@admin.user, CalendarNote).resolve, note
    assert_not_includes CalendarNotePolicy::Scope.new(@member.user, CalendarNote).resolve, note
  end

  def test_show
    assert_permit @member, note_on(@robotics), :show?
  end

  def test_new
    assert_permit @member, CalendarNote, :new?
    assert_permit @admin, CalendarNote, :new?
  end

  def test_create
    assert_write @admin, note_on(@drama)
    assert_write @admin, note_on(nil)

    assert_write @manager, note_on(@robotics)
    assert_write @manager, note_on(@robotics_jr)
    assert_no_write @manager, note_on(@drama)

    assert_no_write @member, note_on(@robotics)
    assert_no_write @member, note_on(@drama)
    assert_no_write @member, note_on(nil)
  end

  def test_create_on_people
    assert_write @member, note_on(@member)
    assert_no_write @member, note_on(@manager)
    assert_no_write @member, note_on(@outsider)

    assert_write @manager, note_on(@member)
    assert_write @manager, note_on(@junior)
    assert_no_write @manager, note_on(@outsider)
    assert_no_write @manager, note_on(@admin)

    assert_write @admin, note_on(@outsider)
  end

  def test_update
    assert_permit @manager, note_on(@robotics), :update?
    assert_permit @manager, note_on(@robotics), :edit?
    assert_not_permit @member, note_on(@robotics), :update?
    assert_not_permit @member, note_on(@robotics), :edit?
    assert_not_permit @member, note_on(nil), :update?
  end

  def test_destroy
    assert_permit @admin, note_on(nil), :destroy?
    assert_permit @member, note_on(@member), :destroy?
    assert_not_permit @member, note_on(nil), :destroy?
    assert_not_permit @member, note_on(@robotics), :destroy?
  end

  private

  def create_person(name, admin: false)
    user = User.create!(email: "#{name}@example.com", password: "Password1!", admin: admin)
    Person.create!(user: user, first_name: name.capitalize, last_name: "Example")
  end

  def note_on(noteable)
    CalendarNote.new(name: "Note", start_time: 1.day.from_now, noteable: noteable)
  end

  def assert_permit(person, record, action)
    assert CalendarNotePolicy.new(person.user, record).public_send(action), "#{person.first_name} should be allowed #{action}"
  end

  def assert_not_permit(person, record, action)
    assert_not CalendarNotePolicy.new(person.user, record).public_send(action), "#{person.first_name} should not be allowed #{action}"
  end

  def assert_write(person, note)
    %i[create? update? destroy?].each { |action| assert_permit person, note, action }
  end

  def assert_no_write(person, note)
    %i[create? update? destroy?].each { |action| assert_not_permit person, note, action }
  end
end
