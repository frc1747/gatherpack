# Optional words for a checklist's overall and for each item, in place of the
# defaults (Checklists::WORDS): "Eligible" / "Not Eligible". Blank uses the
# default.
class AddStatusWordsToChecklistsAndItems < ActiveRecord::Migration[8.1]
  def change
    %i[checklists checklist_items].each do |table|
      add_column table, :met_word, :string
      add_column table, :pending_word, :string
      add_column table, :not_met_word, :string
    end
  end
end
