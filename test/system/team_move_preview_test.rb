require "application_system_test_case"
require_relative "../support/checklists_world"

# The preview answers the form with a plain page, so the browser must load it
# rather than hand it to Turbo (which refuses a 200 response to a form post).
class TeamMovePreviewTest < ApplicationSystemTestCase
  include Warden::Test::Helpers
  include ChecklistsWorld

  setup do
    Capybara.app_host = "http://localhost"
    Capybara.always_include_port = true
    build_checklists_world
    @alumni = create_world_team("Alumni", parent: @club)
    @first = create_world_person("Firstmover", @members)
    @second = create_world_person("Secondmover", @members)
  end

  teardown do
    Capybara.app_host = nil
    Warden.test_reset!
  end

  test "choose two people and a team, preview, confirm" do
    with_settings(feature_checklists: "true", feature_housekeeping: "true") do
      login_as person(:admin).user
      visit team_move_people_path(@members)

      check "select_#{@first.id}"
      check "select_#{@second.id}"
      select "Alumni", from: "to_team_id"
      click_on "Check the move"

      assert_text "2 people will move from Members to Alumni."
      click_on "Move 2"

      assert_text "Moved 2 to Alumni."
      assert @alumni.memberships.exists?(person: @first)
      assert @alumni.memberships.exists?(person: @second)
      assert_not @members.memberships.exists?(person: @first)
    end
  end
end
