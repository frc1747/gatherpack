module Checklists
  # "Who this passes" (spec §9.6): evaluates a draft item, or the draft
  # population, for everyone covered, without storing anything. Counts by
  # status with the first ten names each.
  class Preview
    LIMIT = 10

    attr_reader :counts, :names, :sentence

    def initialize(checklist, item: nil, rules: nil)
      evaluator = Evaluator.new(checklist, items: item ? [ item ] : nil, rules: rules)
      ids = evaluator.covered_ids
      results = evaluator.call(ids).transform_values { |row| row[item ? item.id : nil] }
      people = Person.where(id: ids).pluck(:id, :display_name).to_h
      grouped = results.group_by { |_, result| result.status }
      @counts = STATUSES.index_with { |status| Array(grouped[status]).size }
      @names = grouped.transform_values { |rows| rows.map { |id, _| people[id] }.compact.sort.first(LIMIT) }
      @sentence = item ? item.describe : "Covers #{ids.size} #{"person".pluralize(ids.size)}"
      @item = item
    end

    # Whether this previews one item (its words are the defaults) rather than
    # the overall (the checklist's words).
    def item?
      @item.present?
    end

    def total
      counts.values.sum
    end
  end
end
