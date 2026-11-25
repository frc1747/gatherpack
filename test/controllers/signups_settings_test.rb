require "test_helper"
require_relative "../support/signups_world"

# The organizers setting on the Settings page: a plain text box where the
# settings-inputs seam isn't merged, a badge-and-team picker where it is.
class SignupsSettingsTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include SignupsWorld

  setup do
    host! "localhost"
    build_signups_world
    sign_in person(:admin).user
  end

  test "the organizers setting is registered with a plain-words description" do
    setting = Settings.get(:signups_organizers)

    assert_equal "Sign-ups", setting.group
    assert_no_match(/One per line|Badge name >/, setting.description)
  end

  test "the page shows the setting with a text box when there are no pickers" do
    skip if Settings.respond_to?(:input)

    with_settings(signups_organizers: "Sheet Organizer > Club") do
      get settings_path

      assert_response :success
      assert_select "textarea[name='settings[signups_organizers]']", text: /Sheet Organizer > Club/
    end
  end

  test "the page shows the saved badge and team in pickers" do
    skip unless Settings.respond_to?(:input)

    with_settings(signups_organizers: "Sheet Organizer > Club") do
      get settings_path

      assert_response :success
      assert_select "select[name='settings[signups_organizers][rows][0][badge]'] option[selected]", text: "Sheet Organizer"
      assert_select "select[name='settings[signups_organizers][rows][0][team]'] option[selected]", text: "Club"
    end
  end

  test "only admin-assigned badges are offered" do
    skip unless Settings.respond_to?(:input)
    create_world_badge("Open Badge").update!(permission: :has_account)

    get settings_path

    assert_select "select[name='settings[signups_organizers][rows][0][badge]'] option", text: "Sheet Organizer"
    assert_select "select[name='settings[signups_organizers][rows][0][badge]'] option", text: "Open Badge", count: 0
  end

  test "saving the page unchanged writes the same text" do
    skip unless Settings.respond_to?(:input)

    with_settings(signups_organizers: "Sheet Organizer > Club\r\nAlcohol License") do
      post update_settings_path, params: { settings: { signups_organizers: { rows: {
        "0" => { line: "Sheet Organizer > Club", badge: "Sheet Organizer", team: "Club" },
        "1" => { line: "Alcohol License", badge: "Alcohol License", team: "" },
        "2" => { line: "", badge: "", team: "" }
      } } } }

      assert_equal "Sheet Organizer > Club\r\nAlcohol License", Settings[:signups_organizers]
    end
  end

  test "picking a badge and team writes the line the reader parses" do
    skip unless Settings.respond_to?(:input)

    with_settings(signups_organizers: "") do
      post update_settings_path, params: { settings: { signups_organizers: { rows: {
        "0" => { line: "", badge: "Sheet Organizer", team: "Club" }
      } } } }

      assert_equal "Sheet Organizer > Club", Settings[:signups_organizers]
      assert_equal [ [ @organizer_badge, @club ] ], SignupSheet.organizer_grants
    end
  end
end
