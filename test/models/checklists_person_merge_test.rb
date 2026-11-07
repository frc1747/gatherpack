require "test_helper"
require_relative "../support/checklists_world"

# Runs only where people can be merged (feature/person-merge is present).
class ChecklistsPersonMergeTest < ActiveSupport::TestCase
  include ChecklistsWorld

  COLUMNS = %w[
    checklists.created_by_id checklist_organizers.person_id checklist_rules.person_id checklist_grants.created_by_id
    checklist_attestations.person_id checklist_attestations.attested_by_id checklist_excuses.person_id
    checklist_excuses.created_by_id checklist_lists.recorded_by_id checklist_results.person_id checklist_refreshes.person_id
  ].freeze

  setup do
    skip "people can't be merged here" unless defined?(GatherPack::PersonMerge)
  end

  test "every column checklists adds is covered by a merge" do
    uncovered = COLUMNS.reject { |name| GatherPack::PersonMerge.covers?(*name.split(".")) }

    assert_empty uncovered
  end

  test "the kept person's results stay and are refreshed" do
    build_checklists_world
    checklist = create_world_checklist
    add_rule(checklist, :include, :team, team: @members)
    item = add_item(checklist, :badge, "Safety", { badge_ids: [ @safety.id ] })
    give_badge(:member2, @safety)

    with_feature do
      refresh(checklist)
      kept = ChecklistResult.where(person: person(:member)).pluck(:id)

      merge(keep: person(:member), drop: person(:member2))

      results = ChecklistResult.where(checklist: checklist, person: person(:member))
      assert_equal kept.sort, results.pluck(:id).sort
      assert results.all?(&:stale?)
      assert ChecklistRefresh.where(checklist: checklist).exists?

      refresh(checklist)
      assert_equal "met", stored_status(checklist, :member, item)
    end
  end

  test "the preview warns when a checklist's rules name both people" do
    build_checklists_world
    checklist = create_world_checklist
    add_rule(checklist, :include, :person, person: person(:member))
    add_rule(checklist, :exclude, :person, person: person(:member2))

    assert_match "named in the rules of 1 checklist.", Checklists::MergeChecks.rules(person(:member2).id, person(:member).id)
    assert_nil Checklists::MergeChecks.rules(person(:rookie).id, person(:member).id)
  end

  private

  def merge(keep:, drop:)
    assert PersonMerger.new(keep_nid: keep.neat_id, drop_nid: drop.neat_id, keep_login: "keep").merge(actor: User.find_by!(admin: true))
  end
end
