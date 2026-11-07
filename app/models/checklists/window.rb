module Checklists
  # A span of dates as an item sees it, already resolved against the as-of
  # moment. starts_on nil means "from the beginning"; ends_on nil means "up to
  # now". Times outside it don't count.
  Window = Struct.new(:starts_on, :ends_on, :as_of, keyword_init: true) do
    # Resolves the window fields of a checklist or item (starts_on, or
    # starts_within_amount/unit for "within the last N days or months";
    # ends_on) against as_of.
    def self.for(record, as_of, fallback: nil)
      starts_on = Window.start_for(record, as_of)
      ends_on = record.ends_on
      if fallback
        starts_on ||= fallback.starts_on unless Window.own_start?(record)
        ends_on ||= fallback.ends_on
      end
      new(starts_on: starts_on, ends_on: ends_on, as_of: as_of)
    end

    def self.own_start?(record)
      record.starts_on.present? || record.starts_within_amount.present?
    end

    def self.start_for(record, as_of)
      return record.starts_on if record.starts_on.present?
      return unless record.starts_within_amount.present?

      amount = record.starts_within_amount.to_i
      as_of.to_date - (record.starts_within_unit == "months" ? amount.months : amount.days)
    end

    def start_time
      starts_on&.in_time_zone&.beginning_of_day
    end

    # The end of the last day, never past as_of.
    def end_time
      ends_on ? [ ends_on.in_time_zone.end_of_day, as_of ].min : as_of
    end

    def cover?(time)
      return false if time.nil?

      (start_time.nil? || time >= start_time) && time <= end_time
    end

    def to_s
      from = starts_on ? I18n.l(starts_on, format: :long) : nil
      to = ends_on ? I18n.l(ends_on, format: :long) : "now"
      from ? "#{from} to #{to}" : "up to #{to}"
    end
  end
end
