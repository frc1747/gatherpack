require "test_helper"
require_relative "../support/checklists_world"
require_relative "../support/checklists_test_kinds"

class ChecklistRelativeDateTest < ActiveSupport::TestCase
  include ChecklistsWorld

  setup do
    Checklists.register_item_kind(:joined_since, ChecklistsTestKinds::JoinedSince)
    build_checklists_world
    @checklist = create_world_checklist
  end

  teardown do
    Checklists.unregister_item_kind(:joined_since)
  end

  test "on or after a date resolves to that date" do
    date = Checklists::RelativeDate.from_config({ "mode" => "date", "date" => "2026-09-01" })

    assert_equal Date.new(2026, 9, 1), date.resolve(Time.zone.parse("2027-01-01"))
    assert_equal "on or after #{I18n.l(Date.new(2026, 9, 1), format: :long)}", date.describe
    assert_nil date.next_change_at(Time.current)
  end

  test "within the last N days or months resolves against the as-of moment and moves at midnight" do
    months = Checklists::RelativeDate.from_config({ "mode" => "within", "amount" => 12, "unit" => "months" })
    days = Checklists::RelativeDate.from_config({ "mode" => "within", "amount" => "1", "unit" => "days" })

    assert_equal Date.new(2025, 11, 6), months.resolve(Time.zone.parse("2026-11-06 15:00"))
    assert_equal Date.new(2026, 11, 5), days.resolve(Time.zone.parse("2026-11-06 15:00"))
    assert_equal "within the last 12 months", months.describe
    assert_equal "within the last 1 day", days.describe
    assert_equal Time.zone.parse("2026-11-07 00:00"), months.next_change_at(Time.zone.parse("2026-11-06 15:00"))
  end

  test "blank or malformed values mean no date" do
    assert_nil Checklists::RelativeDate.from_config(nil)
    assert_nil Checklists::RelativeDate.from_config({ "mode" => "" })
    assert_nil Checklists::RelativeDate.from_config({ "mode" => "date", "date" => "not a date" })
    assert_nil Checklists::RelativeDate.from_config({ "mode" => "within", "amount" => 0, "unit" => "days" })
    assert_nil Checklists::RelativeDate.from_config({ "mode" => "within", "amount" => 3, "unit" => "years" })
  end

  test "a kind's relative date setting is cast from form params" do
    assert_equal({ "since" => { "mode" => "within", "amount" => 30, "unit" => "days" } },
      ChecklistsTestKinds::JoinedSince.normalize_config({ "since" => { "mode" => "within", "amount" => "30", "unit" => "days", "date" => "" } }))
    assert_equal({ "since" => { "mode" => "date", "date" => "2026-09-01" } },
      ChecklistsTestKinds::JoinedSince.normalize_config({ "since" => { "mode" => "date", "date" => "2026-09-01", "amount" => "" } }))
    assert_equal({ "since" => nil }, ChecklistsTestKinds::JoinedSince.normalize_config({ "since" => { "mode" => "" } }))
  end

  test "a kind reads it resolved against the as-of moment" do
    item = add_item(@checklist, :joined_since, "New", { since: { mode: "within", amount: 10, unit: "days" } })

    assert_equal "met", evaluate(@checklist, :member, item).status
    travel_to(30.days.from_now) { assert_equal "not_met", evaluate(@checklist, :member, item).status }
  end

  test "copying shifts an on-or-after date and keeps a within-the-last one" do
    fixed = add_item(@checklist, :joined_since, "Fixed", { since: { mode: "date", date: "2026-09-01" } })
    add_item(@checklist, :joined_since, "Moving", { since: { mode: "within", amount: 3, unit: "months" } })

    keys = Checklists::Copier.new(@checklist).date_changes.map(&:key)
    assert_includes keys, "#{fixed.id}.config.since"
    copy = Checklists::Copier.new(@checklist).call(title: "Next", by: person(:admin))

    assert_equal({ "mode" => "date", "date" => "2027-09-01" }, copy.checklist_items.find_by(label: "Fixed").config["since"])
    assert_equal({ "mode" => "within", "amount" => 3, "unit" => "months" }, copy.checklist_items.find_by(label: "Moving").config["since"])
  end
end
