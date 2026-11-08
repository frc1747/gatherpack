require "test_helper"
require_relative "../support/commitments_world"

class CommitmentMonthlyReminderJobTest < ActiveJob::TestCase
  include CommitmentsWorld

  # The 1st at 9:30 AM, site time (UTC unless a test says otherwise).
  FIRST = "2026-11-01 09:30".freeze

  setup do
    build_commitments_world
    @gateway = Gateway::ResendSendingGateway.create!(name: "Resend", api_token: "re_test", sender: "noreply@example.com")
    @shifts = create_remindable("Shifts")
    @hours = create_remindable("Hours")
    @events = create_remindable("Events")
    clear_enqueued_jobs
  end

  test "someone owing three gets one email listing each" do
    run_job do
      assert_emails_to %w[ kid@example.com member@example.com membertwo@example.com ]
      body = emails.find { |email| email[:address] == "member@example.com" }[:body]
      assert_equal 1, emails.count { |email| email[:address] == "member@example.com" }
      %w[ Shifts Hours Events ].each { |title| assert_includes body, title }
      assert_includes body, "<p>Hi Member,</p>"
      assert_includes body, "/people/#{person(:member).neat_id}/commitments"
      assert_equal "What you still owe", emails.first[:subject]
      refute_match(/commitment/i, ActionController::Base.helpers.strip_tags(emails.first[:body]) + emails.first[:subject])
    end
  end

  test "people who have met everything get nothing" do
    [ @shifts, @hours, @events ].each { |commitment| credit(commitment, :member2) }
    credit(@shifts, :member)

    run_job do
      assert_emails_to %w[ kid@example.com member@example.com ]
      body = emails.find { |email| email[:address] == "member@example.com" }[:body]
      assert_not_includes body, "Shifts"
      assert_includes body, "Hours"
    end
  end

  test "someone who has met all three gets no email" do
    [ @shifts, @hours, @events ].each { |commitment| credit(commitment, :member) }

    run_job { assert_not_includes emails.map { |email| email[:address] }, "member@example.com" }
  end

  test "an unticked, ended or not yet started commitment is left out" do
    @hours.update!(monthly_reminder: false)
    @events.update!(ends_on: Date.new(2026, 10, 31))
    @shifts.update!(starts_on: Date.new(2026, 11, 2))
    run_job { assert_empty emails }

    @shifts.update!(starts_on: Date.new(2026, 11, 1))
    run_job(at: "2026-12-01 09:30") do
      body = emails.find { |email| email[:address] == "member@example.com" }[:body]
      assert_includes body, "Shifts"
      assert_not_includes body, "Hours"
      assert_not_includes body, "Events"
    end
  end

  test "a second run in the same month sends nothing, the next month does" do
    run_job { assert_equal 3, emails.size }
    assert_equal Date.new(2026, 11, 1), @shifts.reload.monthly_reminded_on

    run_job(at: "2026-11-01 15:00") { assert_empty emails }
    run_job(at: "2026-11-02 09:30") { assert_empty emails }
    run_job(at: "2026-12-01 09:30") { assert_equal 3, emails.size }
    assert_equal Date.new(2026, 12, 1), @shifts.reload.monthly_reminded_on
  end

  test "it sends only on the 1st, from 9 AM" do
    run_job(at: "2026-11-01 08:59") { assert_empty emails }
    run_job(at: "2026-11-15 09:30") { assert_empty emails }
    assert_nil @shifts.reload.monthly_reminded_on
  end

  test "a missed month isn't made up later" do
    run_job(at: "2026-11-02 09:00") { assert_empty emails }
    run_job(at: "2026-11-30 09:00") { assert_empty emails }
    run_job(at: "2026-12-01 09:30") { assert_equal 3, emails.size }
  end

  test "the 1st at 9 AM is the site's time zone" do
    with_settings(time_zone: "America/Chicago") do
      run_job(at: "2026-11-01 14:30") { assert_empty emails }
      run_job(at: "2026-11-01 15:30") { assert_equal 3, emails.size }
    end
  end

  test "nothing sends without an email gateway" do
    @gateway.destroy!
    run_job do
      assert_empty enqueued_jobs
      assert_nil @shifts.reload.monthly_reminded_on
    end
  end

  test "nothing sends while the flag or commitments is off" do
    travel_to Time.zone.parse(FIRST) do
      with_settings(feature_commitments: "true") do
        CommitmentMonthlyReminderJob.perform_now
      end
      with_settings(feature_commitment_monthly_reminders: "true") do
        CommitmentMonthlyReminderJob.perform_now
      end
    end
    assert_empty enqueued_jobs
    assert_nil @shifts.reload.monthly_reminded_on
  end

  test "a group is reminded together: credit for one member counts for the group" do
    Relationship.create!(parent: person(:member), child: person(:kid), relationship_type: @parent_of, created_by: person(:admin))
    [ @hours, @events ].each { |commitment| commitment.update!(monthly_reminder: false) }
    @shifts.update!(group_relationship_type: @parent_of)
    credit(@shifts, :kid)
    @shifts.reload

    run_job { assert_emails_to %w[ membertwo@example.com ] }
  end

  private

  def create_remindable(title)
    create_world_commitment(title, starts_on: Date.new(2026, 10, 1), ends_on: Date.new(2026, 12, 31), monthly_reminder: true)
  end

  def credit(commitment, name)
    commitment.commitment_adjustments.create!(person: person(name), credits: commitment.base_amount, reason: "Done")
  end

  def run_job(at: FIRST)
    clear_enqueued_jobs
    travel_to Time.zone.parse(at) do
      with_settings(feature_commitments: "true", feature_commitment_monthly_reminders: "true") do
        CommitmentMonthlyReminderJob.perform_now
        yield
      end
    end
  end

  def emails
    enqueued_jobs.select { |job| job[:job] == SendEmailJob }.map do |job|
      { address: job[:args][1], subject: job[:args][2], body: job[:args][3] }
    end
  end

  def assert_emails_to(addresses)
    assert_equal addresses.sort, emails.map { |email| email[:address] }.sort
  end
end
