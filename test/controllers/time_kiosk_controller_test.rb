require "test_helper"

class TimeKioskControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    host! "localhost"
    @team = Team.create!(name: "Robotics", team_type: team_types(:one))
    @period = TimeClockPeriod.create!(name: "Build Season", team: @team, start_time: 1.week.ago, end_time: 1.week.from_now)
    _, @member = create_person("member", team: @team)
    Token.create!(value: "8675309", tokenable: @member)
    @admin_user, = create_person("admin", admin: true)
  end

  test "a card scanned in the 5700 reader format finds its holder" do
    sign_in @admin_user

    post time_kiosk_path, params: { time_kiosk: { tool: "find_token", token_value: "5700" + 8675309.to_s(16) } }

    assert_response :success
    assert_select "h2", "Found Person"
    assert_select "h3", @member.identifier_name
  end

  private

  def create_person(name, team: nil, manager: false, admin: false)
    user = User.create!(email: "#{name}@example.com", password: "Password1!", admin: admin)
    person = Person.create!(user: user, first_name: name.capitalize, last_name: "Test")
    Membership.create!(person: person, team: team, manager: manager) if team
    [ user, person ]
  end
end
