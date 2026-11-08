require "test_helper"
require_relative "../support/checklists_world"

class ChecklistCopyTest < ActiveSupport::TestCase
  include ChecklistsWorld

  setup do
    build_checklists_world
    @checklist = create_world_checklist("Trip 2026", ends_on: Date.new(2099, 5, 1))
    @safety_next = create_world_badge("Safety 2027")
    @item = add_item(@checklist, :badge, "Safety", { badge_ids: [ @safety.id ] }, due_on: Date.new(2026, 12, 1))
    @group = add_item(@checklist, :any_of, "Either")
    @child = add_item(@checklist, :age, "Age", { min: 12, on: "2026-10-01" }, parent: @group)
    @relative = add_item(@checklist, :attested, "Handbook", { statement: "Handbook read" }, starts_within_amount: 12, starts_within_unit: "months")
    add_rule(@checklist, :include, :team, team_id: @members.id)
    add_rule(@checklist, :exclude, :badge, item: @item, badge_id: @viewer_badge.id)
    @checklist.checklist_grants.create!(badge: @viewer_badge, item_ids: [ @item.id ], access: :full)
    ChecklistExcuse.create!(item: @item, person: person(:member), reason: "Injured", created_by: person(:club_manager))
    refresh(@checklist)
    ChecklistList.record!(@checklist, by: person(:admin))
  end

  test "proposes every fixed date shifted, and leaves relative dates alone" do
    changes = Checklists::Copier.new(@checklist, shift_months: 12).date_changes.to_h { |change| [ change.key, [ change.old, change.proposed ] ] }

    assert_equal [ Date.new(2026, 9, 1), Date.new(2027, 9, 1) ], changes["checklist.starts_on"]
    assert_equal [ Date.new(2099, 5, 1), Date.new(2100, 5, 1) ], changes["checklist.ends_on"]
    assert_equal [ Date.new(2026, 12, 1), Date.new(2027, 12, 1) ], changes["#{@item.id}.due_on"]
    assert_equal [ Date.new(2026, 10, 1), Date.new(2027, 10, 1) ], changes["#{@child.id}.config.on"]
    assert_not changes.keys.any? { |key| key.start_with?(@relative.id) }
  end

  test "matches records named with a year to the shifted name" do
    replacements = Checklists::Copier.new(@checklist).replacements.index_by(&:record)

    assert_equal @safety_next, replacements[@safety].proposed
    assert_not replacements.key?(@viewer_badge), "no year in its name"
  end

  test "copies items, rules, grants and organizers into a draft; nothing else" do
    copy = Checklists::Copier.new(@checklist).call(title: "Trip 2027", by: person(:club_manager),
      dates: { "checklist.ends_on" => "2028-07-15" }, replace: { "Badge:#{@safety.id}" => @safety_next.id })

    assert copy.draft?
    assert_equal "Trip 2027", copy.title
    assert_equal Date.new(2027, 9, 1), copy.starts_on
    assert_equal Date.new(2028, 7, 15), copy.ends_on, "edited proposal"
    assert_equal 4, copy.checklist_items.count
    new_item = copy.checklist_items.find_by(label: "Safety")
    assert_equal [ @safety_next.id ], new_item.config["badge_ids"]
    assert_equal Date.new(2027, 12, 1), new_item.due_on
    assert_equal "2027-10-01", copy.checklist_items.find_by(label: "Age").config["on"]
    assert_equal copy.checklist_items.find_by(label: "Either"), copy.checklist_items.find_by(label: "Age").parent
    assert_equal 12, copy.checklist_items.find_by(label: "Handbook").starts_within_amount
    assert_equal 1, copy.population_rules.count
    assert_equal 1, new_item.checklist_rules.count
    assert_equal [ new_item.id ], copy.checklist_grants.first.item_ids
    assert_includes copy.organizers, person(:admin)
    assert_includes copy.organizers, person(:club_manager)

    assert_empty ChecklistExcuse.where(item: copy.checklist_items)
    assert_empty copy.checklist_results
    assert_empty copy.checklist_lists
  end

  test "record this list keeps names and statuses as they were" do
    list = @checklist.checklist_lists.first
    row = list.rows.find { |entry| entry["name"] == "MemberTwo World" }
    assert_equal "not_met", row["overall"]

    give_badge(:member2, @safety)
    refresh(@checklist)
    assert_equal "not_met", list.reload.rows.find { |entry| entry["name"] == "MemberTwo World" }["overall"]
    assert_equal "Trip 2026", list.configuration["title"]
  end

  test "housekeeping archives checklists ended before a date, skipping one another requires" do
    ended = create_world_checklist("Old", starts_on: Date.new(2025, 9, 1), ends_on: Date.new(2026, 6, 30))
    required = create_world_checklist("Required", starts_on: Date.new(2025, 9, 1), ends_on: Date.new(2026, 6, 30))
    add_item(@checklist, :checklist, "Required", { checklist_id: required.id })

    with_settings(checklists_archive_after: "2026-07-01") do
      Checklists::Housekeeping.run(Date.new(2026, 11, 1))

      assert ended.reload.archived?
      assert required.reload.active?
      assert_includes required.problems.join, "still requires it"
      assert @checklist.reload.active?
    end
  end

  test "housekeeping by days after the end, and pruning archived results" do
    ended = create_world_checklist("Old", starts_on: Date.new(2025, 9, 1), ends_on: Date.new(2026, 6, 30))
    add_item(ended, :has_login, "Login")
    refresh(ended)
    list = ChecklistList.record!(ended, by: person(:admin))

    with_settings(checklists_archive_after: "30", checklists_prune_results_after: "60") do
      Checklists::Housekeeping.run(Date.new(2026, 7, 20))
      assert ended.reload.active?, "only 20 days after the end"

      Checklists::Housekeeping.run(Date.new(2026, 8, 5))
      assert ended.reload.archived?
      assert ended.checklist_results.exists?

      Checklists::Housekeeping.run(Date.new(2026, 9, 1))
      assert_empty ended.checklist_results
      assert ChecklistList.exists?(list.id), "recorded lists stay"
    end
  end

  test "archived checklists aren't refreshed" do
    @checklist.update!(status: :archived)

    assert_empty Checklists::Refresher.new(@checklist).call
  end

  test "impact compares a draft change with the stored results" do
    impact = Checklists::Impact.new(@checklist, items: [ @checklist.checklist_items.new(id: SecureRandom.uuid, kind: "has_login", label: "Login") ])

    sentence = impact.sentences.join
    assert_match "would go from Not Started to Complete", sentence
    assert_match "MemberTwo World", sentence
  end
end
