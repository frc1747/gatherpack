require "application_system_test_case"

class CheckinsTest < ApplicationSystemTestCase
  include Devise::Test::IntegrationHelpers

  setup do
    @event = events(:one)
    @event.update!(name: "Spring Workday")
    %w[Carol\ Smith Dan\ Smithers Frank\ Jones].each do |name|
      first, last = name.split
      Person.create!(first_name: first, last_name: last, display_name: name)
    end

    users(:one).update!(admin: true)
    sign_in users(:one)
  end

  test "checking people in from the event page" do
    visit event_path(@event)

    fill_in "candidate_q", with: "smi"
    within("#candidates") do
      assert_no_text "Frank Jones"
      within(find(".list-group-item", text: "Carol Smith")) { click_on "Add" }
      assert_text "Added"
      within(find(".list-group-item", text: "Dan Smithers")) { click_on "Add" }
    end

    within("#checkins") do
      assert_text "Carol Smith"
      assert_text "Dan Smithers"
    end
    assert_selector "#checkins_count", text: "3"
    take_screenshot if ENV["SCREENSHOTS"]
  end
end
