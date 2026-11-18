require "test_helper"

# Searches that can reach people, their logins or their cards pass the
# signed-in user to Ransack, so searchable attributes can depend on who is
# searching.
class RansackAuthObjectSecTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  # Records the auth_object each ransackable_attributes call receives, while
  # a test is listening.
  module RecordAuthObject
    def ransackable_attributes(auth_object = nil)
      Thread.current[:ransack_auth_objects]&.<<(auth_object)
      super
    end
  end
  [ Person, User, Membership, Checkin, TimeClockPunch, Token, CalendarNote, Question, AuditLog ].each do |model|
    model.singleton_class.prepend(RecordAuthObject)
  end

  setup do
    host! "localhost"
    @team = Team.create!(name: "Den A", team_type: team_types(:one))
    @user = User.create!(email: "viewer@example.com", password: "Password1!")
    person = Person.create!(user: @user, first_name: "Vera", last_name: "Viewer", birthday: Date.new(2015, 6, 15))
    Membership.create!(person: person, team: @team, manager: true)
    @person = person
    sign_in @user
    Thread.current[:ransack_auth_objects] = []
  end

  teardown do
    Thread.current[:ransack_auth_objects] = nil
  end

  test "the people directory" do
    get people_path, params: { q: { first_name_cont: "Ver" } }

    assert_auth_object_was_the_user
  end

  test "person search" do
    get combo_search_path(q: "Ver", scope: "people", format: :turbo_stream)

    assert_auth_object_was_the_user
  end

  test "managed people search" do
    get combo_search_path(q: "Ver", scope: "managed_people", format: :turbo_stream)

    assert_auth_object_was_the_user
  end

  test "team people search" do
    get combo_search_path(q: "Ver", scope: "team_people:#{@team.id}", format: :turbo_stream)

    assert_auth_object_was_the_user
  end

  test "searching for yourself" do
    get combo_search_path(q: "Ver", scope: "me", format: :turbo_stream)

    assert_auth_object_was_the_user
  end

  # Only admins search users by email, so the admin finds the viewer by an
  # email that matches no name.
  test "user search" do
    admin = sign_in_admin

    get combo_search_path(q: "viewer@", scope: "users", format: :turbo_stream)

    assert_auth_object_was_the_user(admin)
    assert_includes response.body, "Vera Viewer"
  end

  test "team memberships" do
    get team_memberships_path(@team), params: { q: { "person.first_name_cont" => "Ver" }, people_q: { first_name_cont: "Ver" } }

    assert_auth_object_was_the_user
  end

  test "calendar birthdays" do
    get "/calendar/calendar.json", params: { birthdays: "1", start_time: "2026-01-01", end_time: "2026-12-31", q: { name_i_cont: "Ver" } }

    assert_auth_object_was_the_user
  end

  test "an event's check-ins" do
    event = Event.create!(name: "Den meeting", start_time: Time.current, event_type: event_types(:one), team: @team)
    Checkin.create!(event: event, person: @person)

    get event_path(event), params: { q: { "person.display_name_cont" => "Ver" } }

    assert_auth_object_was_the_user
  end

  test "a time clock period's punches" do
    period = TimeClockPeriod.create!(name: "Fall", start_time: 1.month.ago, end_time: 1.month.from_now, team: @team)

    get time_clock_period_path(period), params: { q: { "person.display_name_cont" => "Ver" } }

    assert_auth_object_was_the_user
  end

  test "time clock punches" do
    get time_clock_punches_path, params: { q: { "person.display_name_cont" => "Ver" } }

    assert_auth_object_was_the_user
  end

  test "tokens" do
    get tokens_path, params: { q: { value_start: "1" } }

    assert_auth_object_was_the_user
  end

  test "token search" do
    get combo_search_path(q: "1", scope: "tokens", format: :turbo_stream)

    assert_auth_object_was_the_user
  end

  test "calendar notes" do
    get calendar_notes_path, params: { q: { name_cont: "Ver" } }

    assert_auth_object_was_the_user
  end

  test "calendar notes on the calendar" do
    get "/calendar/calendar.json", params: { notes: "1", start_time: "2026-01-01", end_time: "2026-12-31", q: { name_cont: "Ver" } }

    assert_auth_object_was_the_user
  end

  # The questions index only renders for admins today (its "New Question"
  # link asks QuestionPolicy#create? about the class).
  test "questions" do
    admin = sign_in_admin

    get questions_path, params: { q: { title_cont: "Ver" } }

    assert_auth_object_was_the_user(admin)
  end

  test "audit logs" do
    admin = sign_in_admin

    get audit_logs_path, params: { q: { item_type_eq: "Person" } }

    assert_auth_object_was_the_user(admin)
  end

  private

  def sign_in_admin
    admin = User.create!(email: "admin-viewer@example.com", password: "Password1!", admin: true)
    Person.create!(user: admin, first_name: "Ada", last_name: "Admin")
    sign_in admin
    admin
  end

  def assert_auth_object_was_the_user(user = @user)
    recorded = Thread.current[:ransack_auth_objects]
    assert recorded.any?, "no ransack calls were recorded"
    assert recorded.all? { |auth_object| auth_object == user }, "expected every call to pass the user, got #{recorded.map(&:class).uniq}"
  end
end
