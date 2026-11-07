module Checklists
  # The effect of an unsaved change on everyone's overall, against the
  # stored results (spec §9.4): "3 people would go from Done to Not yet",
  # including people the change would stop or start covering.
  # items and rules are the draft tree and population rules, as given to
  # Checklists::Evaluator.
  class Impact
    Move = Struct.new(:from, :to, :names, keyword_init: true)

    def initialize(checklist, items: nil, rules: nil)
      @checklist = checklist
      @evaluator = Evaluator.new(checklist, items: items, rules: rules)
    end

    def moves
      @moves ||= begin
        stored = ChecklistResult.where(checklist_id: @checklist.id, item_id: nil).pluck(:person_id, :status).to_h
        draft = @evaluator.call(@evaluator.covered_ids).transform_values { |row| row[nil].status }
        changed = (stored.keys | draft.keys).filter_map do |id|
          [ id, stored[id], draft[id] ] if stored[id] != draft[id]
        end
        names = Person.where(id: changed.map(&:first)).pluck(:id, :display_name).to_h
        changed.group_by { |_, from, to| [ from, to ] }.map do |(from, to), rows|
          Move.new(from: from, to: to, names: rows.map { |id, _, _| names[id] }.compact.sort)
        end
      end
    end

    def sentences
      moves.map do |move|
        to = move.to ? @checklist.word_for(move.to) : "not covered"
        from = move.from ? @checklist.word_for(move.from) : "not covered"
        "#{move.names.size} #{"person".pluralize(move.names.size)} would go from #{from} to #{to}: #{move.names.to_sentence}"
      end
    end

    def any?
      moves.any?
    end
  end
end
