require "application_system_test_case"
require_relative "../support/intake_world"

# The bulk form on a team's applications page, in a browser: Enter in the
# reason box must not submit the first real button (Approve).
class IntakeBulkDecisionsTest < ApplicationSystemTestCase
  include IntakeWorld
  include Warden::Test::Helpers

  setup do
    Capybara.app_host = "http://localhost"
    Capybara.always_include_port = true
    build_intake_world
    @applicant = create_intake_person("Riley", "Rivera", birthday: 30.years.ago.to_date)
    @application = MembershipApplication.create!(person: @applicant, team: @juniors, registration: @registration, source: :link)
    Intake.rate_limit_store = ActiveSupport::Cache::MemoryStore.new
    @restore_settings = SettingsTestHelper.apply(feature_intake: "true")
    login_as @leader.user
  end

  teardown do
    @restore_settings&.call
    Intake.rate_limit_store = nil
    Capybara.app_host = nil
    Warden.test_reset!
  end

  test "pressing Enter in the reason box approves nobody" do
    visit applications_team_path(@juniors)
    tick = find("#bulk_#{@application.id}")
    tick.check
    reason = find("#bulk_reason_#{@juniors.id}")
    reason.fill_in with: "We're full this year"
    # Turbo keeps window across its visits, so a submission would be seen.
    execute_script("document.getElementById('intake-bulk-#{@juniors.id}').addEventListener('submit', () => { window.bulkSubmitted = true })")
    reason.send_keys(:enter)

    # Nothing is sent, so the page stays as it was, with the row still ticked.
    assert_not evaluate_script("window.bulkSubmitted"), "Enter submitted the bulk form"
    assert_current_path applications_team_path(@juniors)
    assert tick.checked?
    assert_no_text "Approved"
    assert @application.reload.pending?

    within("#intake-bulk-#{@juniors.id}") { accept_confirm { click_on "Deny" } }
    assert_text "Denied 1."
    assert @application.reload.denied?
    assert_equal "We're full this year", @application.reviewer_notes
  end
end
