require "test_helper"
require_relative "../support/commitments_world"

# The organizers setting on the Settings page: a plain text box where the
# settings-inputs seam isn't merged, a badge-and-team picker where it is.
class CommitmentsSettingsTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include CommitmentsWorld

  setup do
    host! "localhost"
    build_commitments_world
    sign_in person(:admin).user
  end

  test "the organizers setting is registered with a plain-words description" do
    setting = Settings.get(:commitments_organizers)

    assert_equal "Commitments", setting.group
    assert_no_match(/One per line|Badge name >/, setting.description)
  end

  test "the page shows the setting with a text box when there are no pickers" do
    skip if Settings.respond_to?(:input)

    with_organizer_grants("Commitment Organizer > Club") do
      get settings_path

      assert_response :success
      assert_select "textarea[name='settings[commitments_organizers]']", text: /Commitment Organizer > Club/
    end
  end

  test "the page shows the saved badge and team in pickers" do
    skip unless Settings.respond_to?(:input)

    with_organizer_grants("Commitment Organizer > Club") do
      get settings_path

      assert_response :success
      assert_select "select[name='settings[commitments_organizers][rows][0][badge]'] option[selected]", text: "Commitment Organizer"
      assert_select "select[name='settings[commitments_organizers][rows][0][team]'] option[selected]", text: "Club"
    end
  end

  test "only admin-assigned badges are offered" do
    skip unless Settings.respond_to?(:input)
    Badge.create!(name: "Open Badge", short: "OB", color: "#336699", badge_type: badge_types(:one), permission: :has_account)

    get settings_path

    assert_select "select[name='settings[commitments_organizers][rows][0][badge]'] option", text: "Commitment Organizer"
    assert_select "select[name='settings[commitments_organizers][rows][0][badge]'] option", text: "Open Badge", count: 0
  end

  test "saving the page unchanged writes the same text" do
    skip unless Settings.respond_to?(:input)
    Badge.create!(name: "Other Organizer", short: "OO", color: "#336699", badge_type: badge_types(:one), permission: :added_by_admin)

    with_organizer_grants("Commitment Organizer > Club\r\nOther Organizer") do
      post update_settings_path, params: { settings: { commitments_organizers: { rows: {
        "0" => { line: "Commitment Organizer > Club", badge: "Commitment Organizer", team: "Club" },
        "1" => { line: "Other Organizer", badge: "Other Organizer", team: "" },
        "2" => { line: "", badge: "", team: "" }
      } } } }

      assert_equal "Commitment Organizer > Club\r\nOther Organizer", Settings[:commitments_organizers]
    end
  end

  test "picking a badge and team writes the line the reader parses" do
    skip unless Settings.respond_to?(:input)

    with_organizer_grants("") do
      post update_settings_path, params: { settings: { commitments_organizers: { rows: {
        "0" => { line: "", badge: "Commitment Organizer", team: "Club" }
      } } } }

      assert_equal "Commitment Organizer > Club", Settings[:commitments_organizers]
      assert_equal [ [ @organizer_badge, @club ] ], with_feature { Commitment.organizer_grants }
    end
  end
end
