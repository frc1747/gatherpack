require "test_helper"
require_relative "../support/checklists_count_world"
require Rails.root.join("db/migrate/20261124150000_move_wrapped_exempt_badge_rules_to_items")

class MoveWrappedExemptBadgeRulesToItemsTest < ActiveSupport::TestCase
  include ChecklistsCountWorld

  setup do
    travel_to Time.zone.parse("2026-10-20 12:00")
    build_commitments_world
    @rookie = Badge.create!(name: "Rookie", short: "R", color: "#336699", badge_type: badge_types(:one), permission: :added_by_admin)
    @other = Badge.create!(name: "Other", short: "O", color: "#336699", badge_type: badge_types(:one), permission: :added_by_admin)
    BadgeAssignment.create!(badge: @rookie, person: person(:member2))
  end

  test "a wrapped checklist's exempt badge rule moves onto its count, and back" do
    commitment = create_world_commitment("Members owe", exempt_badge: @rookie)
    checklist = Checklists::WrapCommitments.new.up.sole
    item = checklist.checklist_items.sole
    # As wrapping used to write it: on the checklist.
    exempt = item.checklist_rules.sole
    exempt.update_columns(item_id: nil)
    other = checklist.checklist_rules.new(effect: :exclude, target_type: :badge, badge_id: @other.id).tap { |rule| rule.save!(validate: false) }
    ChecklistRefresh.where(checklist_id: checklist.id).delete_all

    migrate(:up)
    assert_equal item.id, exempt.reload.item_id
    assert_nil other.reload.item_id, "only the commitment's exempt badge moves"
    assert ChecklistRefresh.exists?(checklist_id: checklist.id, person_id: nil), "queued for a refresh"
    assert checklist.checklist_results.all?(&:stale)

    migrate(:up)
    assert_equal item.id, exempt.reload.item_id, "running it again changes nothing"

    migrate(:down)
    assert_nil exempt.reload.item_id
    assert_equal commitment.exempt_badge_id, exempt.badge_id
  end

  test "checklists that aren't wrapped are left alone" do
    checklist = create_count_checklist
    rule = checklist.checklist_rules.new(effect: :exclude, target_type: :badge, badge_id: @rookie.id).tap { |made| made.save!(validate: false) }

    migrate(:up)
    assert_nil rule.reload.item_id
    assert_not ChecklistRefresh.exists?(checklist_id: checklist.id)
  end

  private

  def migrate(direction)
    ActiveRecord::Migration.suppress_messages { MoveWrappedExemptBadgeRulesToItems.new.migrate(direction) }
  end
end
