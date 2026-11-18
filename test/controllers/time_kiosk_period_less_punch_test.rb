require "test_helper"

class TimeKioskPeriodLessPunchTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  setup do
    host! "localhost"

    @person = Person.create!(first_name: "Pat", last_name: "Punch")
    @token = Token.create!(value: "period-less-token", tokenable: @person)
    @period = TimeClockPeriod.create!(name: "Build Season", start_time: 1.month.ago, end_time: 1.month.from_now, permission: :added_by_user)

    # The kiosk runs under a signed-in kiosk account.
    kiosk_user = User.new(email: "kiosk@example.com", password: "Password1!")
    kiosk_user.kiosk = true if kiosk_user.has_attribute?(:kiosk) # Kiosk accounts come with the security series.
    kiosk_user.save!
    Person.create!(user: kiosk_user, first_name: "Front", last_name: "Kiosk")
    sign_in kiosk_user
  end

  test "find_token shows a person with a closed punch that has no period" do
    start = 3.hours.ago
    TimeClockPunch.create!(person: @person, time_clock_period: @period, start_time: start, end_time: start + 2.hours, created_by: "kiosk")
    TimeClockPunch.create!(person: @person, time_clock_period: nil, start_time: start - 1.day, end_time: start - 1.day + 1.hour, created_by: "kiosk")

    get time_kiosk_path(time_kiosk: { tool: "find_token", token_value: @token.value })

    assert_response :success
    assert_select "dt", text: @period.name
    assert_select "dd", text: "2.0"
    assert_select "dt", text: "No period"
  end

  test "find_token lists an open punch that has no period" do
    TimeClockPunch.create!(person: @person, time_clock_period: nil, start_time: 1.hour.ago, created_by: "kiosk")

    get time_kiosk_path(time_kiosk: { tool: "find_token", token_value: @token.value })

    assert_response :success
    assert_select "h3", text: "Open Punches"
    # Once in the hours summary and once in the open punch row.
    assert_select "dt", text: "No period", count: 2
    assert_select "div.row.my-2 dt", text: "No period", count: 1
  end
end
