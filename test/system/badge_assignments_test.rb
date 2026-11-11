require "application_system_test_case"

class BadgeAssignmentsTest < ApplicationSystemTestCase
  include Devise::Test::IntegrationHelpers

  setup do
    @badge = badges(:one)
    @badge.update!(name: "First Aid")
    %w[Carol\ Smith Dan\ Smithers Eve\ Smithson Frank\ Jones].each do |name|
      first, last = name.split
      person = Person.create!(first_name: first, last_name: last, display_name: name)
      Membership.create!(person: person, team: teams(:one))
    end

    users(:one).update!(admin: true)
    sign_in users(:one)
  end

  test "searching, adding, and removing holders without leaving the page" do
    visit badge_badge_assignments_path(@badge)
    take_screenshot if ENV["SCREENSHOTS"]

    fill_in "candidate_q", with: "smi"
    assert_no_text "Frank Jones"
    take_screenshot if ENV["SCREENSHOTS"]

    within("#candidates") do
      within(find(".list-group-item", text: "Carol Smith")) { click_on "Add" }
      assert_text "Added"
      within(find(".list-group-item", text: "Eve Smithson")) { click_on "Add" }
    end

    within("#badge_assignments") do
      assert_text "Carol Smith"
      assert_text "Eve Smithson"
    end
    assert_selector "#badge_assignments_count", text: "3"
    assert_equal "smi", find_field("candidate_q").value
    take_screenshot if ENV["SCREENSHOTS"]

    within(find("#badge_assignments .list-group-item", text: "Carol Smith")) { click_on "Remove Carol Smith" }
    within("#badge_assignments") { assert_no_text "Carol Smith" }
    assert_selector "#badge_assignments_count", text: "2"
    assert_equal 2, @badge.badge_assignments.count
  end
end
