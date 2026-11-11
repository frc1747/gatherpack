require "test_helper"
require_relative "../support/settings_test_helper"

class TimeKioskManagerClockOutControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include SettingsTestHelper

  setup do
    host! "localhost"
    TimeKioskController::TEST_STORE.clear

    type = team_types(:one)
    club = Team.create!(name: "Club", team_type: type)
    coaches = Team.create!(name: "Coaches", team_type: type, parent_id: club.id)
    @season = TimeClockPeriod.create!(name: "Season", team: club, start_time: 1.day.ago.to_date, end_time: 1.day.from_now.to_date, permission: :added_by_admin)
    @coach = create_person("coach@example.com")
    Membership.create!(person: @coach, team: coaches, manager: true)
    Token.create!(value: "100000009", tokenable: @coach)
    @helper = create_person("helper@example.com")
    Membership.create!(person: @helper, team: coaches)
    @outsider = create_person("outsider@example.com")
    Membership.create!(person: @outsider, team: club)
    @helper_punch = open_punch(@helper)
    @outsider_punch = open_punch(@outsider)

    kiosk_user = create_person("kiosk@example.com").user
    kiosk_user.update!(kiosk: true)
    sign_in kiosk_user
  end

  test "off: no Manager button for a manager whose teams own no period" do
    with_settings(TimeKiosk::ManagerClockOut::SETTING => "false") do
      post time_kiosk_path, params: { time_kiosk: { tool: "find_token", token_value: "100000009" } }
    end
    assert_select "a[data-bs-target='#managerModal']", count: 0
  end

  test "on: the Manager window lists the people they manage and clocks out only them" do
    with_settings(TimeKiosk::ManagerClockOut::SETTING => "true") do
      post time_kiosk_path, params: { time_kiosk: { tool: "find_token", token_value: "100000009" } }
      assert_select "a[data-bs-target='#managerModal']", count: 1
      assert_select "#managerModal", text: /Season \[1\]/
      assert_select "#managerModal img[title=?]", @helper.identifier_name
      assert_select "#managerModal img[title=?]", @outsider.identifier_name, count: 0

      post time_kiosk_path, params: { time_kiosk: { tool: "punch_out_period", time_clock_period_id: @season.id, person_ref: ref_for(@coach) } }
      assert_select ".alert-success", text: /Clocked out 1 person from Season\./
    end
    assert @helper_punch.reload.end_time
    assert_nil @outsider_punch.reload.end_time
  end

  test "a period id that names no period is refused" do
    with_settings(TimeKiosk::ManagerClockOut::SETTING => "true") do
      post time_kiosk_path, params: { time_kiosk: { tool: "punch_out_period", time_clock_period_id: SecureRandom.uuid, person_ref: ref_for(@coach) } }
    end
    assert_select ".alert-warning", text: /can't clock out this period/
    assert_nil @helper_punch.reload.end_time
  end

  private

  def ref_for(person)
    person.signed_id(purpose: :time_kiosk, expires_in: 5.minutes)
  end

  def open_punch(person)
    TimeClockPunch.create!(person: person, time_clock_period: @season, start_time: 1.hour.ago, created_by: "kiosk")
  end

  def create_person(email)
    user = User.create!(email: email, password: "Password1!")
    Person.create!(user: user, first_name: "Test", last_name: email.split("@").first.capitalize)
  end
end
