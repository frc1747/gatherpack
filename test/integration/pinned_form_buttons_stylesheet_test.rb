require "test_helper"

class PinnedFormButtonsStylesheetTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    host! "localhost"

    @path = Rails.root.join("tmp", "pinned-form-buttons-test-#{Process.pid}.pstore").to_s
    File.delete(@path) if File.exist?(@path)
    @original_store = Settings.instance.store
    Settings.instance.store = PStore.new(@path, true)

    @user = User.create!(email: "admin@example.com", password: "Password1!", admin: true)
    Person.create!(user: @user, first_name: "Ada", last_name: "Admin")
    sign_in @user
  end

  teardown do
    Settings.instance.store = @original_store
    File.delete(@path) if File.exist?(@path)
  end

  test "is a feature that starts off" do
    assert_equal "Pinned form buttons", GatherPack::Features.all.find { |f| f.key == :pinned_form_buttons }.label
    assert_not GatherPack::Features.enabled?(:pinned_form_buttons)
  end

  test "links the stylesheet only while the feature is on" do
    get settings_path
    assert_response :success
    assert_select "link[rel=stylesheet][href*='pinned_form_buttons']", count: 0

    Settings[:feature_pinned_form_buttons] = "true"
    get settings_path
    assert_response :success
    assert_select "link[rel=stylesheet][href*='pinned_form_buttons']:not([data-turbo-track])", count: 1
  end
end
