require "test_helper"

# Searching people by their login or card is for admins. For anyone else a
# condition on a login email or card value is ignored, so a matching and a
# non-matching guess list the same people.
class PeopleSearchTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    host! "localhost"
    @pack = Team.create!(name: "Pack", team_type: team_types(:one))
    @den_a = Team.create!(name: "Den A", team_type: team_types(:one), parent: @pack)
    @den_b = Team.create!(name: "Den B", team_type: team_types(:one), parent: @pack)
    @student = create_person("student@example.com", "Sam", "Student", @den_a)
    @classmate = create_person("classmate@example.com", "Cora", "Classmate", @den_b)
    Token.create!(tokenable: @classmate, value: "8675309")
    @admin = create_person("admin@example.com", "Ada", "Admin", @den_a, admin: true)
  end

  test "a member can't learn another member's card value from the people directory" do
    sign_in @student.user

    assert_same_people people_path, "#people",
      { q: { tokens_value_start: "8675" } }, { q: { tokens_value_start: "9999" } }
  end

  test "a member can't recover another member's card value digit by digit" do
    sign_in @student.user

    recovered = +""
    7.times do
      digit = (0..9).find do |d|
        get people_path, params: { q: { tokens_value_start: "#{recovered}#{d}" } }
        listed?("#people", @classmate)
      end
      break unless digit
      recovered << digit.to_s
    end

    assert_not_equal "8675309", recovered
  end

  test "a member can't learn another member's login email from the people directory" do
    sign_in @student.user

    assert_same_people people_path, "#people",
      { q: { user_email_start: "classmate@" } }, { q: { user_email_start: "zzz" } }
  end

  test "a member can't reach a login email by combining it with a name" do
    sign_in @student.user

    assert_same_people people_path, "#people",
      { q: { display_name_or_user_email_cont: "classmate@" } }, { q: { display_name_or_user_email_cont: "zzz" } }
  end

  test "a member can't learn a card value from a team's roster" do
    Membership.create!(person: @student, team: @pack)
    sign_in @student.user

    assert_same_people team_memberships_path(@pack), "#people_grid",
      { people_q: { tokens_value_start: "8675" } }, { people_q: { tokens_value_start: "9999" } }
  end

  test "a member can't learn an attendee's card value from an event's check-ins" do
    event = create_event_with(@classmate)
    sign_in @student.user

    assert_same_people event_path(event), "#checkins",
      { q: { person_tokens_value_start: "8675" } }, { q: { person_tokens_value_start: "9999" } }
  end

  test "a member can't learn an attendee's login email from an event's check-ins" do
    event = create_event_with(@classmate)
    sign_in @student.user

    assert_same_people event_path(event), "#checkins",
      { q: { person_user_email_start: "classmate@" } }, { q: { person_user_email_start: "zzz" } }
  end

  test "a member can't sort people by birthday" do
    @student.update!(birthday: Date.new(2015, 1, 1))
    @classmate.update!(birthday: Date.new(2014, 1, 1))
    sign_in @student.user

    get people_path, params: { q: { s: "birthday asc" } }
    by_birthday = css_select("#people").text
    get people_path, params: { q: { s: "birthday desc" } }

    assert_equal by_birthday, css_select("#people").text
  end

  test "a member finds people by name" do
    event = create_event_with(@classmate)
    Membership.create!(person: @student, team: @pack)
    sign_in @student.user

    get people_path, params: { q: { display_name_i_cont: "cora" } }
    assert listed?("#people", @classmate)
    assert_not listed?("#people", @student)

    get team_memberships_path(@pack), params: { people_q: { display_name_i_cont: "cora" } }
    assert listed?("#people_grid", @classmate)
    assert_not listed?("#people_grid", @student)

    get event_path(event), params: { q: { person_display_name_i_cont: "zzz" } }
    assert_not listed?("#checkins", @classmate)
    get event_path(event), params: { q: { person_display_name_i_cont: "cora" } }
    assert listed?("#checkins", @classmate)
  end

  test "an admin finds a person by card value or login email" do
    event = create_event_with(@classmate)
    sign_in @admin.user

    get people_path, params: { q: { tokens_value_start: "8675" } }
    assert listed?("#people", @classmate)
    get people_path, params: { q: { tokens_value_start: "9999" } }
    assert_not listed?("#people", @classmate)

    get people_path, params: { q: { user_email_start: "classmate@" } }
    assert listed?("#people", @classmate)
    get people_path, params: { q: { user_email_start: "zzz" } }
    assert_not listed?("#people", @classmate)

    get event_path(event), params: { q: { person_tokens_value_start: "9999" } }
    assert_not listed?("#checkins", @classmate)
  end

  test "the people directory offers phone, address and age only to admins" do
    sign_in @student.user
    get people_path
    assert_select "input[name='q[display_name_i_cont]']"
    assert_select "input[name='q[phone_number_i_cont]']", false
    assert_select "input[name='q[address_i_cont]']", false
    assert_select "a.dropdown-item", text: "Age", count: 0

    sign_in @admin.user
    get people_path
    assert_select "input[name='q[phone_number_i_cont]']"
    assert_select "input[name='q[address_i_cont]']"
    assert_select "a.dropdown-item", text: "Age"
  end

  private

  def create_person(email, first, last, team, admin: false)
    user = User.create!(email: email, password: "Password1!", admin: admin)
    person = Person.create!(user: user, first_name: first, last_name: last)
    Membership.create!(person: person, team: team)
    person
  end

  def create_event_with(attendee)
    event = Event.create!(name: "Den meeting", event_type: event_types(:one), team: @den_a, start_time: 1.day.ago, end_time: 1.day.ago + 2.hours)
    Checkin.create!(event: event, person: attendee)
    event
  end

  def listed?(selector, person)
    css_select(selector).text.include?(person.display_name)
  end

  def assert_same_people(path, selector, matching, non_matching)
    get path, params: matching
    assert_response :success
    hit = listed?(selector, @classmate)
    get path, params: non_matching
    miss = listed?(selector, @classmate)

    assert_equal hit, miss, "#{path} answers whether #{matching.inspect} matches #{@classmate.display_name}"
  end
end
