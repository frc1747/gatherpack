require "test_helper"

class TimeKioskScanPanelsTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    host! "localhost"
    TimeKioskController::TEST_STORE.clear
    kiosk_user = User.create!(email: "front-kiosk@example.com", password: "Password1!", kiosk: true)
    Person.create!(user: kiosk_user, first_name: "Front", last_name: "Kiosk")
    sign_in kiosk_user
    @original_panels = TimeKiosk::ScanPanels.all
    @original_view_paths = ActionController::Base.view_paths
    TimeKiosk::ScanPanels.reset!
    ActionController::Base.prepend_view_path Rails.root.join("test/fixtures/views")

    @member = create_person("member@example.com")
    @token = Token.create!(value: "100000001", tokenable: @member)
    @other = create_person("other@example.com")
    Token.create!(value: "100000002", tokenable: @other)
  end

  teardown do
    TimeKiosk::ScanPanels.reset!
    @original_panels.each { |panel| TimeKiosk::ScanPanels.register(panel.key, partial: panel.partial) }
    ActionController::Base.view_paths = @original_view_paths
  end

  test "a scan renders nothing extra when no panel is registered" do
    post time_kiosk_path, params: { time_kiosk: { tool: "find_token", token_value: "100000001" } }

    assert_response :success
    assert_select "h3", text: @member.identifier_name
    assert_select ".test-scan-panel", count: 0
  end

  test "a registered panel renders for the scanned person only" do
    TimeKiosk::ScanPanels.register(:test, partial: "scan_panel_test/panel")

    post time_kiosk_path, params: { time_kiosk: { tool: "find_token", token_value: "100000001" } }

    assert_response :success
    assert_select ".test-scan-panel", count: 1, text: "Panel for #{@member.identifier_name}"
    assert_select ".test-scan-panel", text: /#{@other.identifier_name}/, count: 0
  end

  test "registering a key again replaces the earlier panel" do
    TimeKiosk::ScanPanels.register(:test, partial: "scan_panel_test/missing")
    TimeKiosk::ScanPanels.register(:test, partial: "scan_panel_test/panel")

    assert_equal [ "scan_panel_test/panel" ], TimeKiosk::ScanPanels.all.map(&:partial)
  end

  private

  def create_person(email)
    user = User.create!(email: email, password: "Password1!")
    Person.create!(user: user, first_name: "Test", last_name: email.split("@").first.capitalize)
  end
end
