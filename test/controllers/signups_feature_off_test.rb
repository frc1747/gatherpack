require "test_helper"
require_relative "../support/signups_world"

# Sign-up Sheets are off by default. While off, sign-up pages send people
# away, and event pages, check-ins and notices leave sign-ups alone.
class SignupsFeatureOffTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper
  include Devise::Test::IntegrationHelpers
  include SignupsWorld

  setup do
    host! "localhost"
    travel_to Time.zone.parse("2026-10-11 12:00")
    build_signups_world
    @sheet = create_world_sheet
    @cashier = @sheet.signup_positions.create!(name: "Cashier", capacity: 4)
    @signup = create_world_signup(@cashier, :student)
    clear_enqueued_jobs
  end

  test "the feature is off unless turned on" do
    assert_equal "false", GatherPack::Features.all.find { |feature| feature.key == :signups }.default_enabled.to_s
  end

  test "while off, sign-up pages redirect and nothing else touches sign-ups" do
    with_settings(feature_signups: "false") do
      sign_in person(:admin).user

      [ signup_sheets_path, signup_sheet_path(@sheet), roster_signup_sheet_path(@sheet), edit_signup_sheet_path(@sheet),
        new_signup_sheet_signup_sheet_event_path(@sheet), new_signup_sheet_signup_message_path(@sheet),
        new_signup_sheet_signup_path(@sheet, slot_id: slot_for(@cashier).id) ].each do |path|
        get path
        assert_redirected_to root_path, path
        assert_equal "Sign-up sheets are turned off", flash[:notice]
      end
      assert_no_difference "Signup.count" do
        post signup_sheet_signups_path(@sheet), params: { signup: { signup_slot_id: slot_for(@cashier).id } }
      end
      assert_redirected_to root_path

      get event_path(@event)
      assert_response :success
      assert_select "#event_signups", count: 0

      Checkin.create!(person: person(:student), event: @event)
      assert @signup.reload.active?

      @event.update!(start_time: @event.start_time + 1.hour)
      assert_empty enqueued_emails
    end
  end
end
