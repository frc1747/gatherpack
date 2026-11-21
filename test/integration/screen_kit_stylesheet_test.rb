require "test_helper"

class ScreenKitStylesheetTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    host! "localhost"

    @path = Rails.root.join("tmp", "screen-kit-test-#{Process.pid}.pstore").to_s
    File.delete(@path) if File.exist?(@path)
    @original_store = Settings.instance.store
    Settings.instance.store = PStore.new(@path, true)

    @user = User.create!(email: "admin@example.com", password: "Password1!", admin: true)
    Person.create!(user: @user, first_name: "Nadia", last_name: "Northwind")
    sign_in @user
  end

  teardown do
    Settings.instance.store = @original_store
    File.delete(@path) if File.exist?(@path)
  end

  test "is a feature that starts off" do
    assert_equal "Standard buttons on built-in screens", GatherPack::Features.all.find { |f| f.key == :screen_standard }.label
    assert_not GatherPack::Features.enabled?(:screen_standard)
  end

  test "links the stylesheet only while the feature is on" do
    get settings_path
    assert_response :success
    assert_select "link[rel=stylesheet][href*='screen_kit']", count: 0

    Settings[:feature_screen_standard] = "true"
    get settings_path
    assert_response :success
    assert_select "link[rel=stylesheet][href*='screen_kit'][data-turbo-track=reload]", count: 1
  end
end
