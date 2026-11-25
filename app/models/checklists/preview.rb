module Checklists
  # "Who this passes" (spec §9.6): evaluates a draft item, or the draft
  # population, for everyone covered, without storing anything. Counts by
  # status with the first ten names each.
  class Preview
    LIMIT = 10

    attr_reader :counts, :names, :sentence

    attr_reader :hidden

    # viewer, when given, is who sees the preview: an item's kind may hide
    # some people's results from them (ItemKind.visible_to?), and those
    # are counted only as hidden, for an item and for the population.
    def initialize(checklist, item: nil, rules: nil, viewer: nil)
      evaluator = Evaluator.new(checklist, items: item ? [ item ] : nil, rules: rules)
      ids = evaluator.covered_ids
      if viewer
        # An item preview hides people its kind (or a child's) hides; a
        # population preview hides people whose overall depends on such an
        # item.
        visible = item ? Checklists.visible_person_ids(item, viewer, ids) : ids - Checklists.capped_person_ids(evaluator.items, viewer, ids)
        @hidden = ids.size - visible.size
        ids = visible
      end
      @hidden ||= 0
      results = evaluator.call(ids).transform_values { |row| row[item ? item.id : nil] }
      people = Person.where(id: ids).pluck(:id, :display_name).to_h
      grouped = results.group_by { |_, result| result.status }
      @counts = STATUSES.index_with { |status| Array(grouped[status]).size }
      @names = grouped.transform_values { |rows| rows.map { |id, _| people[id] }.compact.sort.first(LIMIT) }
      @sentence = item ? item.describe : "Covers #{ids.size} #{"person".pluralize(ids.size)}"
    end

    def total
      counts.values.sum
    end
  end
end
