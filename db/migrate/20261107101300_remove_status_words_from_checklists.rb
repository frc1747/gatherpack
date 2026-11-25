# Every checklist now shows the same three status words (Checklists::WORDS).
class RemoveStatusWordsFromChecklists < ActiveRecord::Migration[8.1]
  def change
    remove_column :checklists, :met_word, :string
    remove_column :checklists, :pending_word, :string
    remove_column :checklists, :not_met_word, :string
  end
end
