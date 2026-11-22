require "application_system_test_case"
require_relative "../support/commitments_world"

class CommitmentsTest < ApplicationSystemTestCase
  include Devise::Test::IntegrationHelpers
  include CommitmentsWorld

  setup do
    # config.hosts allows localhost, not Capybara's default 127.0.0.1.
    @always_include_port = Capybara.always_include_port
    Capybara.app_host = "http://localhost"
    Capybara.always_include_port = true

    build_commitments_world
    @commitment = create_world_commitment(starts_on: Date.current.beginning_of_month, ends_on: Date.current.end_of_month)
    @commitment.commitment_sources.create!(kind: "checkins", subject: @outreach)
    sign_in person(:admin).user
  end

  teardown do
    Capybara.app_host = nil
    Capybara.always_include_port = @always_include_port
  end

  test "Remind opens the folded message card in place" do
    with_feature do
      visit commitment_path(@commitment)
      assert_no_field "Subject"

      click_on "Remind (3)"
      assert_field "Subject"
      assert_field "Message"
      assert_button "Send"
      assert_current_path commitment_path(@commitment)
    end
  end
end
