module Checklists
  # A checklist's or an item's own words for its statuses (met_word,
  # pending_word, not_met_word, and a checklist's exempt_word), each falling
  # back to the default (Checklists::WORDS) when blank. An item has no
  # exempt_word: its exempt_label ("Rookie") says why instead.
  module Words
    COLUMNS = { "met" => :met_word, "pending" => :pending_word, "not_met" => :not_met_word,
                "exempt" => :exempt_word }.freeze

    # The columns this record has, for its setup form.
    def self.columns_for(record)
      COLUMNS.select { |_status, column| record.has_attribute?(column) }
    end

    def word_for(status)
      column = COLUMNS[status.to_s]
      (column && has_attribute?(column) && self[column].presence&.strip) || Checklists.word_for(status)
    end
  end
end
