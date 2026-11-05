require "application_system_test_case"

class MembershipsTest < ApplicationSystemTestCase
  include Devise::Test::IntegrationHelpers

  setup do
    @team = teams(:one)
    @people = %w[Carol\ Smith Dan\ Smithers Frank\ Jones].map do |name|
      first, last = name.split
      Person.create!(first_name: first, last_name: last, display_name: name)
    end

    users(:one).update!(admin: true)
    sign_in users(:one)
  end

  test "adding members from the team page" do
    child = Team.create!(name: "Child Crew", team_type: team_types(:one), parent: @team)
    Membership.create!(person: @people.last, team: child)

    visit team_memberships_path(@team)
    within("##{ActionView::RecordIdentifier.dom_id(@people.last, :grid)}") { assert_text "Via Child Crew" }

    fill_in "candidate_q", with: "smi"
    within("#candidates") do
      assert_no_text "Frank Jones"
      within(find(".list-group-item", text: "Carol Smith")) { click_on "Add" }
      assert_text "Added"
    end

    within("#people_grid") { assert_text "Carol Smith" }
    take_screenshot if ENV["SCREENSHOTS"]
    assert @team.people.include?(@people.first)
  end

  test "adding teams from the person page" do
    visit person_memberships_path(people(:two))

    within("#candidates") do
      within(find(".list-group-item", text: "Alpha Team")) { click_on "Add" }
      assert_text "Added"
    end

    within("#memberships") { assert_text "Alpha Team" }
    take_screenshot if ENV["SCREENSHOTS"]
    assert people(:two).teams.include?(@team)
  end
end
