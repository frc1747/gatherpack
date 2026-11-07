require "test_helper"
require_relative "../../support/intake_world"

class Intake::EntryTest < ActiveSupport::TestCase
  include IntakeWorld

  setup { build_intake_world }

  test "a link works once" do
    entry, token = create_intake_entry

    assert_equal entry, Intake::Entry.find_by_token(token)
    entry.verify!(create_intake_person("Riley", "Rivera"))
    assert_nil Intake::Entry.find_by_token(token)
    assert_nil entry.reload.token_digest
  end

  test "a link stops working when it expires" do
    entry, token = create_intake_entry

    travel_to(entry.expires_at + 1.second) { assert_nil Intake::Entry.find_by_token(token) }
    travel_to(entry.expires_at - 1.minute) { assert_equal entry, Intake::Entry.find_by_token(token) }
  end

  test "a new link replaces the old one" do
    entry, old_token = create_intake_entry
    new_token = entry.issue_token!

    assert_nil Intake::Entry.find_by_token(old_token)
    assert_equal entry, Intake::Entry.find_by_token(new_token)
  end

  test "links last intake_link_hours" do
    with_settings(intake_link_hours: "2") do
      entry, = create_intake_entry
      assert_in_delta 2.hours.from_now, entry.expires_at, 5.seconds
    end
  end

  test "only the token's digest is stored" do
    entry, token = create_intake_entry

    assert_equal Intake.digest(token), entry.token_digest
    assert_not_equal token, entry.token_digest
    assert_equal 22, token.length # 128 bits, URL-safe base64
  end

  test "the email and facts are encrypted in the database" do
    entry, = create_intake_entry(email: "secret.person@example.com")
    raw = Intake::Entry.connection.select_one("SELECT email, facts FROM intake_entries WHERE id = #{Intake::Entry.connection.quote(entry.id)}")

    assert_not_includes raw["email"], "secret.person"
    assert_not_includes raw["facts"], @juniors.id
    assert_equal "secret.person@example.com", entry.reload.email
    assert_equal [ @juniors.id ], entry.team_ids
  end

  test "an entry must choose a team" do
    entry = @registration.entries.new(first_name: "Riley", last_name: "Rivera", email: "riley@example.com")

    assert_not entry.valid?
    assert_includes entry.errors.full_messages, "Choose at least one team."
  end

  test "unverified entries expire after intake_entry_days" do
    old, = create_intake_entry
    old.update_column(:created_at, 8.days.ago)
    fresh, = create_intake_entry(email: "fresh@example.com")

    assert_equal [ old ], Intake::Entry.expired.to_a
    with_settings(intake_entry_days: "10") { assert_empty Intake::Entry.expired }
    assert_not_includes Intake::Entry.expired, fresh
  end

  test "the network prefix keeps three parts of the address" do
    assert_equal "203.0.113.*", Intake.ip_prefix("203.0.113.77")
    assert_equal "2001:db8:85a3:*", Intake.ip_prefix("2001:db8:85a3::8a2e:370:7334")
    assert_nil Intake.ip_prefix("not an address")
  end

  test "a registration is open between its dates" do
    assert @registration.open?
    assert_includes Intake::Registration.open_now, @registration
    travel_to(@registration.closes_at + 1.second) { assert_not @registration.open? }
    travel_to(@registration.opens_at - 1.second) { assert_not @registration.open? }
    @registration.update!(closes_at: nil)
    travel_to(10.years.from_now) { assert @registration.open? }
  end

  test "copying shifts the dates by the gap between open and close" do
    copy = @registration.copy
    gap = @registration.closes_at - @registration.opens_at

    assert copy.new_record?
    assert_in_delta @registration.opens_at + gap, copy.opens_at, 1.second
    assert_equal @registration.apply_team_ids.sort, copy.apply_team_ids.sort
    assert_equal [ @joined_badge.id ], copy.badge_ids
    copy.save!
    assert_not_equal @registration.slug, copy.slug
  end

  test "the slug is random and unguessable by default" do
    assert_match(/\A[a-z0-9]{12}\z/, @registration.slug)
  end

  test "archived registrations are hidden by date" do
    @registration.update!(opens_at: 60.days.ago, closes_at: 40.days.ago)

    assert_includes Intake::Registration.not_archived, @registration
    with_settings(intake_archive_days: "30") { assert_not_includes Intake::Registration.not_archived, @registration }
    with_settings(intake_archive_days: "50") { assert_includes Intake::Registration.not_archived, @registration }
  end

  test "needing a guardian goes by birthday and the age limit, and no birthday means yes" do
    assert Intake.needs_guardian?(birthday: nil)
    assert Intake.needs_guardian?(birthday: 17.years.ago.to_date)
    assert_not Intake.needs_guardian?(birthday: 18.years.ago.to_date - 1.day)
    with_settings(guardianship_age_limit: "21") { assert Intake.needs_guardian?(birthday: 20.years.ago.to_date) }
    assert Intake.needs_guardian?(birth_year: Date.current.year - 18)
    assert_not Intake.needs_guardian?(birth_year: Date.current.year - 19)
  end
end
