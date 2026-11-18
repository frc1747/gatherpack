require "test_helper"
require_relative "../support/forms_world"
require_relative "../support/settings_test_helper"

# A world form is open to family, so 7 people owe a response (A1, A2, B1,
# three leaders, the assistant) and A1's and A2's parents can nudge.
class FormAutoReminderJobTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper
  include FormsWorld
  include SettingsTestHelper

  setup do
    build_person_fields_world
    Gateway::SmtpSendingGateway.create!(name: "Test mail", configuration: {})
    @form = create_world_form(closes_at: 2.days.from_now, auto_reminder_days: 3)
    @sandwich = add_choice(@form, "Sandwich", [ "Slim 1", "Slim 4" ], required: true)
  end

  test "new forms start at three days while the flag is on, and at none while it's off" do
    with_reminders { assert_equal 3, Form.new.auto_reminder_days }
    assert_equal 0, Form.new.auto_reminder_days
    assert_equal 0, Form.columns_hash["auto_reminder_days"].default.to_i
  end

  test "turning the flag on sends nothing for a form made while it was off" do
    @form.update!(auto_reminder_days: 0)
    form = create_world_form("Made Off", closes_at: 2.days.from_now)
    assert_equal 0, form.auto_reminder_days
    assert_no_enqueued_jobs only: SendEmailJob do
      run_job
    end
    assert_equal 0, form.form_reminders.count
  end

  test "a copy gets its own reminder once its deadline is set" do
    run_job
    copy = @form.reload.duplicate!(title: "Copy")
    assert copy.auto_reminded_at
    copy.update!(closes_at: 2.days.from_now, status: :open)
    assert_nil copy.reload.auto_reminded_at
    assert copy.auto_reminder_at
  end

  test "a deadline cleared and set again re-arms it" do
    run_job
    @form.reload.update!(closes_at: nil)
    @form.update!(closes_at: 2.days.from_now)
    assert_nil @form.reload.auto_reminded_at
  end

  test "a draft shows when its reminder would go out" do
    draft = create_world_form("Draft", status: :draft, closes_at: 5.days.from_now, auto_reminder_days: 3)
    assert_in_delta (5.days.from_now - 3.days).to_f, draft.auto_reminder_at.to_f, 5
  end

  test "sends once inside the window, recorded as automatic" do
    run_job
    assert_equal 1, @form.form_reminders.count
    reminder = @form.form_reminders.first
    assert_nil reminder.sent_by
    assert reminder.filter["automatic"]
    assert_equal 7, reminder.recipient_count
    assert @form.reload.auto_reminded_at

    assert_no_difference -> { @form.form_reminders.count } do
      run_job
    end
  end

  test "emails only the people who still owe" do
    respond(@form, :a1, as: :a1, answers: { @sandwich.key => "Slim 1" })
    assert_enqueued_jobs 6, only: SendEmailJob do
      with_reminders { FormAutoReminderJob.perform_now }
    end
  end

  test "waits until the window" do
    @form.update!(closes_at: 5.days.from_now)
    run_job
    assert_equal 0, @form.form_reminders.count
    assert_nil @form.reload.auto_reminded_at
  end

  test "does nothing for zero days, no deadline, a closed form or a passed deadline" do
    @form.update!(auto_reminder_days: 0)
    nodate = create_world_form("No Date", auto_reminder_days: 3)
    closed = create_world_form("Closed", closes_at: 2.days.from_now, status: :closed)
    late = create_world_form("Late", closes_at: 1.hour.ago, auto_reminder_days: 3)
    run_job
    [ @form, nodate, closed, late ].each { |form| assert_equal 0, form.form_reminders.count, form.title }
  end

  test "does nothing while the flag, forms or the gateway are off" do
    with_settings(feature_forms: "true", feature_forms_auto_reminders: "false") { FormAutoReminderJob.perform_now }
    with_settings(feature_forms: "false", feature_forms_auto_reminders: "true") { FormAutoReminderJob.perform_now }
    Gateway::SmtpSendingGateway.delete_all
    run_job
    assert_equal 0, @form.form_reminders.count
    assert_nil @form.reload.auto_reminded_at
  end

  test "a concurrent run can't send twice" do
    stale = Form.find(@form.id)
    assert @form.claim_auto_reminder!
    assert_not stale.claim_auto_reminder!
  end

  test "a later deadline re-arms it, an earlier one doesn't" do
    run_job
    @form.reload.update!(closes_at: 1.day.from_now)
    assert @form.reload.auto_reminded_at
    @form.update!(closes_at: 2.days.from_now)
    assert_nil @form.reload.auto_reminded_at
    run_job
    assert_equal 2, @form.form_reminders.count
  end

  test "a manual reminder doesn't stop it" do
    @form.form_reminders.create!(sent_at: 1.day.ago)
    run_job
    assert_equal 2, @form.form_reminders.count
    assert @form.form_reminders.exists?(sent_by_id: nil)
  end

  test "the list matches the Remind screen's" do
    respond(@form, :a1, as: :a1, answers: { @sandwich.key => "Slim 1" })
    report = FormReport.new(@form, viewer: person(:admin))
    screen = report.rows.reject { |row| %w[ complete no_longer_asked ].include?(row.status) }.map(&:person)
    assert_equal screen.sort_by(&:id), FormPending.new(@form).people.sort_by(&:id)
    assert_equal screen.sort_by(&:id), FormPending.new(@form, among: report.people).people.sort_by(&:id)
  end

  test "guardians who would only nudge wait for the second reminder" do
    run_job
    assert_equal false, @form.form_reminders.first.guardians_included
    @form.reload.update!(closes_at: 3.days.from_now)
    run_job
    assert_equal true, @form.form_reminders.order(:sent_at).last.guardians_included
  end

  private

  def run_job
    with_reminders { FormAutoReminderJob.perform_now }
  end

  def with_reminders(&block)
    with_settings(feature_forms: "true", feature_forms_auto_reminders: "true", &block)
  end
end
