# A checklist has one end date now: ends_on stops counting and freezes
# results. A cutoff earlier than the end, or with no end, becomes the end,
# unless it falls before the start, which ends_on isn't allowed to.
class RemoveCutoffOnFromChecklists < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL.squish
      UPDATE checklists SET ends_on = cutoff_on
      WHERE cutoff_on IS NOT NULL AND (ends_on IS NULL OR cutoff_on < ends_on)
        AND (starts_on IS NULL OR cutoff_on >= starts_on)
    SQL
    # What's stored was computed live, not at the end of Until: start over,
    # so the next run stores real end-of-day answers.
    execute "UPDATE checklists SET computed_at = NULL, next_refresh_at = NULL WHERE ends_on IS NOT NULL"
    remove_column :checklists, :cutoff_on
  end

  def down
    add_column :checklists, :cutoff_on, :date
  end
end
