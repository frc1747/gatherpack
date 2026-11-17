module Checklists
  # A checklist's or an item's own words for its statuses (met_word,
  # pending_word, not_met_word), each falling back to the default
  # (Checklists::WORDS) when blank. "Not counted" has no setting: a label
  # ("Rookie") says why instead.
  module Words
    COLUMNS = { "met" => :met_word, "pending" => :pending_word, "not_met" => :not_met_word }.freeze

    def word_for(status)
      column = COLUMNS[status.to_s]
      (column && self[column].presence&.strip) || Checklists.word_for(status)
    end
  end
end
