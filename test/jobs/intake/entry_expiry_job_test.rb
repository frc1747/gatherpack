require "test_helper"
require_relative "../../support/intake_world"

class Intake::EntryExpiryJobTest < ActiveJob::TestCase
  include IntakeWorld

  setup { build_intake_world }

  test "unverified entries past intake_entry_days are deleted; others stay" do
    old, = create_intake_entry(email: "old@example.com")
    old.update_column(:created_at, 8.days.ago)
    fresh, = create_intake_entry(email: "fresh@example.com")
    verified, = create_intake_entry(email: "done@example.com")
    verified.update_columns(created_at: 8.days.ago, verified_at: 7.days.ago)

    Intake::EntryExpiryJob.perform_now

    assert_not Intake::Entry.exists?(old.id)
    assert Intake::Entry.exists?(fresh.id)
    assert Intake::Entry.exists?(verified.id)
  end

  test "the expired hook runs for each deleted entry" do
    old, = create_intake_entry
    old.update_column(:created_at, 8.days.ago)
    Hook.create!(name: "Note expiry", event: "intake_entries - expired", code: "Rails.logger.info('expired')")

    with_intake do
      assert_difference -> { Intake::Entry.count }, -1 do
        Intake::EntryExpiryJob.perform_now
      end
    end
  end

  test "network prefixes are forgotten after 30 days" do
    entry, = create_intake_entry
    entry.update_columns(created_ip_prefix: "203.0.113.*", verified_at: 31.days.ago, created_at: 31.days.ago)

    Intake::EntryExpiryJob.perform_now

    assert_nil entry.reload.created_ip_prefix
  end

  test "opened and closed hooks fire for dates in the last hour" do
    Hook.create!(name: "Opened", event: "intake_registrations - opened", code: "(Thread.current[:intake_hooks] ||= []) << 'opened'")
    Hook.create!(name: "Closed", event: "intake_registrations - closed", code: "(Thread.current[:intake_hooks] ||= []) << 'closed'")
    @registration.update_columns(opens_at: 30.minutes.ago, closes_at: 10.minutes.ago)

    with_intake { Intake::RegistrationDatesJob.perform_now }

    assert_equal %w[opened closed], Thread.current[:intake_hooks]
  ensure
    Thread.current[:intake_hooks] = nil
  end

  test "intake's hook events are in the catalog" do
    assert_includes Hook.catalog, "intake_entries - verified"
    assert_includes Hook.catalog, "membership_applications - approved"
    assert_includes Hook.catalog, "intake_registrations - create"
  end
end
