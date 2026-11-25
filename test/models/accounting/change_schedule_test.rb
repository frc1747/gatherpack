require "test_helper"
require_relative "../../support/accounting_world"

class Accounting::ChangeScheduleTest < ActiveSupport::TestCase
  include AccountingWorld

  setup do
    @gateway = create_quickbooks_gateway
    @schedule = -> { Accounting::ChangeSchedule.new(@gateway) }
  end

  # The time a check began, as the sync stores it (a minute early).
  def checked_at(time)
    @gateway.record_state!(last_change_check_at: time - Accounting::Sync::OVERLAP)
  end

  def choose(word)
    @gateway.update!(change_check: word)
  end

  test "a source with no choice checks every 15 minutes, and is always due" do
    assert_equal "15m", @schedule.().word
    checked_at(Time.utc(2026, 11, 25, 10, 0))
    assert @schedule.().due?(Time.utc(2026, 11, 25, 10, 0, 30))
  end

  test "a source never checked is due, except one checked only on request" do
    assert @schedule.().due?
    choose("manual")
    assert_not @schedule.().due?
  end

  test "manual is never due" do
    choose("manual")
    checked_at(Time.utc(2026, 11, 1))
    assert_not @schedule.().due?(Time.utc(2026, 11, 25, 12))
  end

  test "hourly is due once in each clock hour, and made up when a tick was missed" do
    choose("hourly")
    checked_at(Time.utc(2026, 11, 25, 10, 0, 5))
    assert_not @schedule.().due?(Time.utc(2026, 11, 25, 10, 15))
    assert_not @schedule.().due?(Time.utc(2026, 11, 25, 10, 45))
    assert @schedule.().due?(Time.utc(2026, 11, 25, 11, 0))
    assert @schedule.().due?(Time.utc(2026, 11, 25, 13, 30))
  end

  test "twice a day checks once after 6:00 and once after 18:00" do
    choose("twice_daily")
    checked_at(Time.utc(2026, 11, 25, 6, 0, 3))
    assert_not @schedule.().due?(Time.utc(2026, 11, 25, 6, 15))
    assert_not @schedule.().due?(Time.utc(2026, 11, 25, 17, 45))
    assert @schedule.().due?(Time.utc(2026, 11, 25, 18, 0))

    checked_at(Time.utc(2026, 11, 25, 18, 0, 3))
    assert_not @schedule.().due?(Time.utc(2026, 11, 25, 23, 45))
    assert_not @schedule.().due?(Time.utc(2026, 11, 26, 5, 45))
    assert @schedule.().due?(Time.utc(2026, 11, 26, 6, 0))
  end

  test "a window is made up at the next tick when the server missed it" do
    choose("twice_daily")
    checked_at(Time.utc(2026, 11, 24, 18, 0, 3))
    assert_not @schedule.().due?(Time.utc(2026, 11, 25, 5, 59))
    # Down at 6:00 and back at 6:40: due at once, then not again.
    assert @schedule.().due?(Time.utc(2026, 11, 25, 6, 40))
    checked_at(Time.utc(2026, 11, 25, 6, 40, 4))
    assert_not @schedule.().due?(Time.utc(2026, 11, 25, 6, 45))
    assert_not @schedule.().due?(Time.utc(2026, 11, 25, 17, 59))
  end

  test "a check from before the last boundary is due even after a long outage" do
    choose("twice_daily")
    checked_at(Time.utc(2026, 11, 20, 6, 0))
    assert @schedule.().due?(Time.utc(2026, 11, 25, 3, 0))
  end

  test "once a day checks once after 6:00" do
    choose("daily")
    checked_at(Time.utc(2026, 11, 25, 6, 0, 2))
    assert_not @schedule.().due?(Time.utc(2026, 11, 25, 18, 30))
    assert_not @schedule.().due?(Time.utc(2026, 11, 26, 5, 45))
    assert @schedule.().due?(Time.utc(2026, 11, 26, 6, 0))
  end

  test "the times are in the site's time zone" do
    choose("daily")
    with_settings(time_zone: "America/New_York") do
      # 6:00 in New York on 25 Nov is 11:00 UTC.
      checked_at(Time.utc(2026, 11, 24, 11, 0, 2))
      assert_not @schedule.().due?(Time.utc(2026, 11, 25, 10, 45))
      assert @schedule.().due?(Time.utc(2026, 11, 25, 11, 0))
    end
  end

  test "the schedule in words" do
    assert_equal "Checks QuickBooks every 15 minutes.", @schedule.().sentence
    choose("twice_daily")
    assert_equal "Checks QuickBooks twice a day (6 am and 6 pm).", @schedule.().sentence
    choose("manual")
    assert_equal "Checks QuickBooks only when someone clicks Sync now.", @schedule.().sentence
  end

  test "the stored words are the only choices" do
    assert_equal %w[ 15m hourly twice_daily daily manual ], Accounting::ChangeSchedule.words
    Accounting::ChangeSchedule.words.each { |word| assert @gateway.update(change_check: word) }
    assert @gateway.update(change_check: "")
    assert_not @gateway.update(change_check: "weekly")
    assert_includes @gateway.errors[:change_check].to_s, "isn't one of the choices"
  end

  test "the setting is a select on the form, 15 minutes unless chosen" do
    input = @gateway.field_input(:change_check)
    assert_equal "Check for changes", input[:label]
    assert_equal :select, input[:as]
    assert_equal "15m", input[:selected]
    assert_equal [ "Every 15 minutes", "Every hour", "Twice a day (6 am and 6 pm)", "Once a day (6 am)", "Only when someone clicks Sync now" ], input[:choices].map(&:first)
    assert_includes @gateway.fields, :change_check
    choose("daily")
    assert_equal "daily", @gateway.field_input(:change_check)[:selected]
  end

  test "an unknown stored word falls back to the default" do
    @gateway.update_columns(configuration: @gateway.configuration.merge("change_check" => "weekly"))
    schedule = Accounting::ChangeSchedule.new(@gateway.reload)

    assert_equal "15m", schedule.word
    assert_not schedule.manual?
    assert_equal "Checks QuickBooks every 15 minutes.", schedule.sentence
    assert_equal "15m", @gateway.field_input(:change_check)[:selected]

    checked_at(Time.utc(2026, 11, 25, 10))
    schedule = Accounting::ChangeSchedule.new(@gateway.reload)
    assert schedule.due?(Time.utc(2026, 11, 25, 10, 5)), "after a check, the default (every 15 minutes) is always due, without raising"
  end

  test "the form's hint names the source and mentions notifications only when it has them" do
    assert_match "QuickBooks notifications, when set up, still arrive at once", @gateway.field_input(:change_check)[:hint]

    ledgers = Gateway::LedgerSource.create!(name: "Member ledgers")
    hint = ledgers.change_check_input[:hint]
    assert_no_match(/notifications|QuickBooks/, hint)
    assert_match "Sync now always checks at once.", hint
  end

  test "the webhook problem no longer promises 15 minutes" do
    @gateway.update!(webhook_verifier_token: nil)
    assert_no_match "15 minutes", @gateway.webhook_problem
  end
end
