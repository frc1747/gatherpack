# A commitment's exempt badge means "doesn't owe", not "isn't on it":
# wrapped checklists (Checklists::WrapCommitments) wrote it as a
# checklist-level exclude rule, which left its holders off the checklist.
# Moves each such rule onto the wrapped count item, so holders are on the
# checklist as exempt from the count, and queues those checklists for a
# refresh (ChecklistClockJob picks the marks up). Only rules matching the
# commitment's exempt badge move; down moves them back.
class MoveWrappedExemptBadgeRulesToItems < ActiveRecord::Migration[8.1]
  def up
    move(from: "rules.item_id IS NULL", to: "items.id")
  end

  def down
    move(from: "rules.item_id = items.id", to: "NULL")
  end

  private

  def move(from:, to:)
    moved = select_values(<<~SQL.squish)
      UPDATE checklist_rules rules SET item_id = #{to}, updated_at = NOW()
      FROM checklist_items items
      JOIN commitments ON commitments.id = items.commitment_id
      WHERE items.wrapped AND items.kind = 'count'
        AND rules.checklist_id = items.checklist_id AND #{from}
        AND rules.effect = 1 AND rules.target_type = 1
        AND rules.badge_id = commitments.exempt_badge_id
      RETURNING rules.checklist_id
    SQL
    mark(moved.uniq)
  end

  # As Checklists.mark(checklists, :all), without the job: active and draft
  # checklists only, their results flagged stale until the refresh. An
  # archived checklist is never refreshed, so its results stay as they are.
  # Raw SQL, so the moved rules get no audit entry (ChecklistRule has
  # has_paper_trail): models can change after this migration is written.
  def mark(checklist_ids)
    return if checklist_ids.empty?

    ids = checklist_ids.map { |id| connection.quote(id) }.join(", ")
    refreshed = "SELECT id FROM checklists WHERE id IN (#{ids}) AND status IN (0, 1)"
    execute(<<~SQL.squish)
      INSERT INTO checklist_refreshes (checklist_id, person_id, created_at)
      SELECT id, NULL, NOW() FROM (#{refreshed}) refreshed
      ON CONFLICT (checklist_id, person_id) DO NOTHING
    SQL
    execute("UPDATE checklist_results SET stale = TRUE WHERE checklist_id IN (#{refreshed})")
  end
end
