require "test_helper"

class TimeKioskUsersTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    host! "localhost"
    TimeKioskController::TEST_STORE.clear

    @parent = Team.create!(name: "Club", team_type: team_types(:one))
    @kiosk_team = Team.create!(name: "Kiosk", team_type: team_types(:one), parent: @parent)
    @child = Team.create!(name: "Kiosk Helpers", team_type: team_types(:one), parent: @kiosk_team)
  end

  test "a direct member of the team opens the kiosk" do
    person = create_person("kiosk@example.com")
    Membership.create!(person: person, team: @kiosk_team)

    assert_kiosk_opens_for person.user
  end

  test "an admin opens the kiosk" do
    user = create_person("admin@example.com").user
    user.update!(admin: true)

    assert_kiosk_opens_for user
  end

  test "a member of a child team is turned away" do
    person = create_person("child@example.com")
    Membership.create!(person: person, team: @child)

    assert_kiosk_refuses person.user
  end

  test "a manager of a parent team is turned away" do
    person = create_person("manager@example.com")
    Membership.create!(person: person, team: @parent, manager: true)

    assert_kiosk_refuses person.user
  end

  test "an unrelated user is turned away" do
    assert_kiosk_refuses create_person("other@example.com").user
  end

  test "a user without a person is turned away" do
    assert_kiosk_refuses User.create!(email: "nobody@example.com", password: "Password1!")
  end

  test "a scan from a user who isn't allowed does nothing" do
    member = create_person("member@example.com")
    token = Token.create!(value: "100000001", tokenable: member)
    sign_in create_person("other@example.com").user

    with_users_team(@kiosk_team) do
      post time_kiosk_path, params: { time_kiosk: { tool: "find_token", token_value: token.value } }
    end

    assert_response :forbidden
  end

  test "a blank setting leaves the kiosk to kiosk accounts and admins" do
    sign_in create_person("other@example.com").user

    with_users_team(nil) do
      get time_kiosk_path
    end

    assert_response :forbidden
  end

  private

  def assert_kiosk_opens_for(user)
    sign_in user

    with_users_team(@kiosk_team) do
      get time_kiosk_path
    end

    assert_response :success
  end

  def assert_kiosk_refuses(user)
    sign_in user

    with_users_team(@kiosk_team) do
      get time_kiosk_path
    end

    assert_response :forbidden
  end

  def with_users_team(team)
    original = TimeKiosk::Config.method(:users_team)
    TimeKiosk::Config.define_singleton_method(:users_team) { team }
    yield
  ensure
    TimeKiosk::Config.define_singleton_method(:users_team, original)
  end

  def create_person(email)
    user = User.create!(email: email, password: "Password1!")
    Person.create!(user: user, first_name: "Test", last_name: email.split("@").first.capitalize)
  end
end
