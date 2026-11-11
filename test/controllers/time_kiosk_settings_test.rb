require "test_helper"

class TimeKioskSettingsTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    host! "localhost"
    TimeKioskController::TEST_STORE.clear

    team = Team.create!(name: "Robotics", team_type: team_types(:one))
    TimeClockPeriod.create!(name: "Build Season", team: team, start_time: 1.day.ago.to_date, end_time: 1.day.from_now.to_date, permission: :added_by_user)
    @member = Person.create!(first_name: "Test", last_name: "Member")
    Membership.create!(person: @member, team: team)
    Token.create!(value: "100000001", tokenable: @member)

    user = User.create!(email: "kiosk@example.com", password: "Password1!")
    Person.create!(user: user, first_name: "Test", last_name: "Kiosk")
    sign_in user
  end

  teardown do
    FileUtils.rm_f(store.path)
  end

  test "a setting saved by another process applies to the next scan" do
    assert_no_difference -> { @member.time_clock_punches.count } do
      scan
    end

    store.transaction { store[:time_kiosk_allow_unassigned] = "false" }

    assert_difference -> { @member.time_clock_punches.count } do
      scan
    end
  end

  private

  def scan
    post time_kiosk_path, params: { time_kiosk: { tool: "find_token", token_value: "100000001" } }
    assert_response :success
  end

  def store
    TimeKiosk::Config.send(:store)
  end
end
