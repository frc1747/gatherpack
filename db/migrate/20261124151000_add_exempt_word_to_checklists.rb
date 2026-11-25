# An optional word for a checklist's "Not required" overall, next to
# met_word, pending_word and not_met_word: a checklist that says "Eligible"
# can say "Exempt". Blank uses the default (Checklists::WORDS). An item has
# no exempt_word: its exempt_label already names what it reads for people it
# doesn't apply to.
class AddExemptWordToChecklists < ActiveRecord::Migration[8.1]
  def change
    add_column :checklists, :exempt_word, :string
  end
end
