module Checklists
  # What an evaluation runs against: the checklist, the as-of moment (now, or
  # the end of the checklist's last day once it has passed) and the checklist's window.
  # Kinds are pure functions of data up to as_of, their item and its window.
  class Context
    attr_reader :checklist, :as_of, :evaluator

    # pinned: a frozen checklist is reading this one as of its own moment.
    def initialize(checklist, as_of: nil, evaluator: nil, pinned: false)
      @checklist = checklist
      @as_of = Context.as_of_for(checklist, as_of || Time.current)
      @evaluator = evaluator
      @pinned = pinned
    end

    def self.as_of_for(checklist, time)
      last = last_moment(checklist)
      last && last < time ? last : time
    end

    def self.last_moment(checklist)
      checklist.ends_on&.in_time_zone(Checklists.time_zone)&.end_of_day
    end

    # The checklist's last day is over at this as-of moment.
    def ended?
      last = Context.last_moment(checklist)
      last.present? && as_of >= last
    end

    # Other checklists must be read as of this moment too, not as they
    # stand today.
    def pinned?
      @pinned || ended?
    end

    # A due date has passed once its day is over, and the last day is over
    # once the checklist has ended, even though as_of is still on that day.
    def past_due?(due_on)
      today = as_of.to_date
      due_on < today || (ended? && due_on == today)
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
