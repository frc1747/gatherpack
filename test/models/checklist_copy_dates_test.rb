require "test_helper"
require_relative "../support/checklists_world"
require_relative "../support/checklists_test_kinds"

# A kind lists the fixed dates in its config (ItemKind.copy_dates) and puts
# the confirmed ones back (apply_copy_dates), so "Copy checklist" shifts
# dates inside its rows too.
class ChecklistCopyDatesTest < ActiveSupport::TestCase
  include ChecklistsWorld

  setup do
    Checklists.register_item_kind(:rows, ChecklistsTestKinds::Rows)
    build_checklists_world
    @checklist = create_world_checklist
    @item = add_item(@checklist, :rows, "Rules", { rows: { "0" => { name: "Summer", share: "10", from: "2026-05-01" }, "1" => { name: "Fall", share: "20" } } })
  end

  teardown do
    Checklists.unregister_item_kind(:rows)
  end

  test "a kind's own dates are proposed shifted, with its labels" do
    change = Checklists::Copier.new(@checklist).date_changes.find { |entry| entry.key == "#{@item.id}.config.rows.0.from" }

    assert_equal Date.new(2026, 5, 1), change.old
    assert_equal Date.new(2027, 5, 1), change.proposed
    assert_equal "Rules: summer starts", change.label
  end

  test "copying applies the shifted or edited dates through the kind" do
    copy = Checklists::Copier.new(@checklist).call(title: "Next", by: person(:admin))
    rows = copy.checklist_items.find_by!(label: "Rules").config["rows"]
    assert_equal "2027-05-01", rows[0]["from"]
    assert_nil rows[1]["from"]

    edited = Checklists::Copier.new(@checklist).call(title: "Edited", by: person(:admin), dates: { "#{@item.id}.config.rows.0.from" => "2027-06-15" })
    assert_equal "2027-06-15", edited.checklist_items.find_by!(label: "Rules").config["rows"][0]["from"]
    assert_equal "2026-05-01", @item.reload.config["rows"][0]["from"], "the original stays"
  end

  test "the default lists date and on-or-after settings, not within-the-last ones" do
    assert_equal [ { key: "on", label: "On", value: Date.new(2026, 10, 1) } ],
      Checklists::Kinds::Age.copy_dates(@checklist.checklist_items.new(kind: "age", config: { "min" => 12, "on" => "2026-10-01" }))
    within = @checklist.checklist_items.new(kind: "x", config: { "since" => { "mode" => "within", "amount" => 3, "unit" => "months" } })
    assert_empty ChecklistsTestKinds::JoinedSince.copy_dates(within)
  end
end
