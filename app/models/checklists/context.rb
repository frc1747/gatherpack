module Checklists
  # What an evaluation runs against: the checklist, the as-of moment (now, or
  # the end of the cutoff day once it has passed) and the checklist's window.
  # Kinds are pure functions of data up to as_of, their item and its window.
  class Context
    attr_reader :checklist, :as_of, :evaluator

    def initialize(checklist, as_of: nil, evaluator: nil)
      @checklist = checklist
      @as_of = Context.as_of_for(checklist, as_of || Time.current)
      @evaluator = evaluator
    end

    def self.as_of_for(checklist, time)
      cutoff = checklist.cutoff_on&.in_time_zone&.end_of_day
      cutoff && cutoff < time ? cutoff : time
    end

    def window
      @window ||= Window.for(checklist, as_of)
    end

    # The item's own dates, or the checklist's where it has none.
    def window_for(item)
      Window.for(item, as_of, fallback: window)
    end

    # Child items' results, applying who each applies to and excuses, for
    # combining kinds ({ item_id => { person_id => Result } }).
    def evaluate_items(items, person_ids)
      evaluator.evaluate_items(items, person_ids)
    end
  end
end
