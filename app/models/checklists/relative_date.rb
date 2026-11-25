module Checklists
  # A date setting as organizers pick it (spec §9.1): "on or after <date>",
  # or "within the last N days | months", resolved against the as-of moment.
  # Kinds use it through a setting of type :relative_date; its config value
  # is { "mode" => "date", "date" => "2026-09-01" } or
  # { "mode" => "within", "amount" => 12, "unit" => "months" }.
  #
  #   date = Checklists::RelativeDate.from_config(item.config["since"])
  #   date&.resolve(context.as_of)   # => a Date
  #   date&.describe                 # => "within the last 12 months"
  class RelativeDate
    UNITS = %w[days months].freeze

    attr_reader :date, :amount, :unit

    def initialize(date: nil, amount: nil, unit: nil)
      @date = date
      @amount = amount
      @unit = unit
    end

    # From a stored config value; nil when it's blank or malformed.
    def self.from_config(value)
      return unless value.is_a?(Hash)

      case value["mode"]
      when "date"
        new(date: Date.iso8601(value["date"].to_s)) if value["date"].present?
      when "within"
        amount = value["amount"].to_i
        new(amount: amount, unit: value["unit"]) if amount.positive? && UNITS.include?(value["unit"])
      end
    rescue Date::Error
      nil
    end

    # The config value for form params ({ mode, date, amount, unit }), or
    # nil when nothing usable was picked.
    def self.cast(params)
      params = params.to_h.stringify_keys
      date = from_config(params)
      date&.to_config
    end

    def relative?
      date.nil?
    end

    def to_config
      relative? ? { "mode" => "within", "amount" => amount, "unit" => unit } : { "mode" => "date", "date" => date.iso8601 }
    end

    # The date it means as of a moment.
    def resolve(as_of)
      return date unless relative?

      as_of.to_date - (unit == "months" ? amount.months : amount.days)
    end

    # When a relative date next moves (the next midnight), else nil.
    def next_change_at(as_of)
      as_of.to_date.tomorrow.in_time_zone.beginning_of_day if relative?
    end

    def shift(months)
      relative? ? self : self.class.new(date: date + months.months)
    end

    def describe
      relative? ? "within the last #{amount} #{amount == 1 ? unit.singularize : unit}" : "on or after #{I18n.l(date, format: :long)}"
    end
  end
end
