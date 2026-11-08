module Checklists
  # The effect of an unsaved change on everyone's overall, against the
  # stored results (spec §9.4): "3 people would go from Complete to Not Started",
  # including people the change would stop or start covering.
  # items and rules are the draft tree and population rules, as given to
  # Checklists::Evaluator. With a viewer, people whose result depends on an
  # item whose kind hides it from them (before or after the change) are
  # counted only as hidden, never named or placed in a move.
  class Impact
    Move = Struct.new(:from, :to, :names, keyword_init: true)

    def initialize(checklist, items: nil, rules: nil, viewer: nil)
      @checklist = checklist
      @evaluator = Evaluator.new(checklist, items: items, rules: rules)
      @viewer = viewer
    end

    def moves
      compute
      @moves
    end

    # How many people would change whom the viewer can't be told about.
    def hidden
      compute
      @hidden
    end

    def sentences
      lines = moves.map do |move|
        from = move.from ? Checklists.word_for(move.from) : "not covered"
        to = move.to ? Checklists.word_for(move.to) : "not covered"
        "#{move.names.size} #{"person".pluralize(move.names.size)} would go from #{from} to #{to}: #{move.names.to_sentence}"
      end
      lines << "#{hidden} more #{"person".pluralize(hidden)} would change, through an item you can't see" if hidden.positive?
      lines
    end

    def any?
      moves.any? || hidden.positive?
    end

    private

    def compute
      return if @moves

      stored = ChecklistResult.where(checklist_id: @checklist.id, item_id: nil).pluck(:person_id, :status).to_h
      draft = @evaluator.call(@evaluator.covered_ids).transform_values { |row| row[nil].status }
      changed = (stored.keys | draft.keys).filter_map do |id|
        [ id, stored[id], draft[id] ] if stored[id] != draft[id]
      end
      capped = capped_ids(changed.map(&:first)).to_set
      @hidden = changed.count { |id, _, _| capped.include?(id) }
      shown = changed.reject { |id, _, _| capped.include?(id) }
      names = Person.where(id: shown.map(&:first)).pluck(:id, :display_name).to_h
      @moves = shown.group_by { |_, from, to| [ from, to ] }.map do |(from, to), rows|
        Move.new(from: from, to: to, names: rows.map { |id, _, _| names[id] }.compact.sort)
      end
    end

    # Capped through the draft items or the items as they are now (a
    # removed item can be the hidden one).
    def capped_ids(ids)
      return [] if @viewer.nil? || ids.empty?

      current = @checklist.top_level_items.includes(children: :children).to_a
      (Checklists.capped_person_ids(@evaluator.items, @viewer, ids) + Checklists.capped_person_ids(current, @viewer, ids)).uniq
    end
  end
end
