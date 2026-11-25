require "test_helper"

class Intake::SettingsPickersTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    host! "localhost"
    @path = Rails.root.join("tmp", "intake-settings-pickers-#{Process.pid}.pstore").to_s
    File.delete(@path) if File.exist?(@path)
    @original_store = Settings.instance.store
    Settings.instance.store = PStore.new(@path, true)

    @admin_user = User.create!(email: "admin@example.com", password: "Password1!", admin: true)
    Person.create!(user: @admin_user, first_name: "Ada", last_name: "Admin")
  end

  teardown do
    Settings.instance.store = @original_store
    File.delete(@path) if File.exist?(@path)
  end

  test "the domain hints description doesn't explain the format" do
    description = Settings.instance.settings[:intake_domain_hints].description

    assert_no_match(/comma/i, description)
  end

  test "the domain hints picker shows each saved domain" do
    skip "needs the settings inputs seam" unless Settings.respond_to?(:input)
    Settings.set(:intake_domain_hints, "x.com, y.com")
    sign_in @admin_user

    get settings_path

    assert_response :success
    assert_select "input[name='settings[intake_domain_hints][items][]'][value='x.com']"
    assert_select "input[name='settings[intake_domain_hints][items][]'][value='y.com']"
  end

  test "saving the domain hints picker unchanged keeps the saved text" do
    skip "needs the settings inputs seam" unless Settings.respond_to?(:input)
    Settings.set(:intake_domain_hints, "x.com,  y.com")
    sign_in @admin_user

    post update_settings_path, params: { settings: { intake_domain_hints: { items: [ "", "x.com", "y.com", "" ] } } }

    assert_equal "x.com,  y.com", Settings[:intake_domain_hints]
  end

  test "removing a domain from the picker saves the shorter list" do
    skip "needs the settings inputs seam" unless Settings.respond_to?(:input)
    Settings.set(:intake_domain_hints, "x.com, y.com")
    sign_in @admin_user

    post update_settings_path, params: { settings: { intake_domain_hints: { items: [ "x.com", "" ] } } }

    assert_equal "x.com", Settings[:intake_domain_hints]
  end
end
