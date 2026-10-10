require "test_helper"

class TimeKioskReturnTimerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    host! "localhost"
    TimeKioskController::TEST_STORE.clear

    @member = create_person("member@example.com")
    @token = Token.create!(value: "100000001", tokenable: @member)
    @unassigned_token = Token.create!(value: "100000002")

    sign_in create_person("kiosk@example.com").user
  end

  test "the profile shows the timer with the configured seconds" do
    with_return_seconds(12) do
      kiosk tool: "find_token", token_value: @token.value
    end

    assert_response :success
    assert_select "h3", text: @member.identifier_name
    assert_timer 12
  end

  test "the not found screen shows the timer" do
    with_return_seconds(30) do
      kiosk tool: "find_token", token_value: @unassigned_token.value
    end

    assert_response :success
    assert_select "#kiosk-content", text: /not found/i
    assert_timer 30
  end

  test "the timer is shown in a Turbo Stream response" do
    with_return_seconds(12) do
      post time_kiosk_path, params: { time_kiosk: { tool: "find_token", token_value: @token.value } }, as: :turbo_stream
    end

    assert_response :success
    assert_includes response.body, %(data-kiosk-return-seconds-value="12")
  end

  test "Welcome has no timer" do
    with_return_seconds(12) do
      get time_kiosk_path
      assert_select "[data-controller=kiosk-return]", count: 0

      kiosk tool: "find_token", token_value: ""
      assert_select "[data-controller=kiosk-return]", count: 0
    end
  end

  test "no timer when the setting is 0" do
    with_return_seconds(0) do
      kiosk tool: "find_token", token_value: @token.value
      assert_select "h3", text: @member.identifier_name
      assert_select "[data-controller=kiosk-return]", count: 0

      kiosk tool: "find_token", token_value: @unassigned_token.value
      assert_select "[data-controller=kiosk-return]", count: 0
    end
  end

  private

  # Minitest 6 no longer ships Object#stub, so swap the reader by hand.
  def with_return_seconds(seconds)
    config = TimeKiosk::Config.singleton_class
    original = config.instance_method(:return_seconds)
    config.define_method(:return_seconds) { seconds }
    yield
  ensure
    config.define_method(:return_seconds, original)
  end

  def create_person(email)
    user = User.create!(email: email, password: "Password1!")
    Person.create!(user: user, first_name: "Test", last_name: email.split("@").first.capitalize)
  end

  def kiosk(**params)
    post time_kiosk_path, params: { time_kiosk: params }
  end

  def assert_timer(seconds)
    assert_select "#kiosk-content [data-controller=kiosk-return]", count: 1 do |timer|
      assert_equal seconds.to_s, timer.first["data-kiosk-return-seconds-value"]
      assert_equal time_kiosk_path, timer.first["data-kiosk-return-url-value"]
      assert_select "[data-kiosk-return-target=message]", text: "Returning in #{seconds}s"
    end
  end
end
