# A typed, user-defined value: the data type, its options (choices, ranges,
# patterns), and the conversions between form input, Ruby values, and the
# stored JSON text. Shared by person fields and anything else that defines
# its own fields. Needs `data_type` (integer) and `options` (jsonb) columns.
module FieldValueType
  extend ActiveSupport::Concern

  PHONE_FORMAT = /\A\+?[\d\s().\-]{7,20}(\s*(x|ext\.?)\s*\d{1,6})?\z/i

  included do
    enum :data_type, { string: 0, text: 1, boolean: 2, date: 3, integer: 4, select: 5, multi_select: 6, phone: 7, email: 8 }, prefix: :type, validate: true

    store_accessor :options, :choices, :choices_setting, :min, :max, :pattern, :pattern_hint

    validate :options_make_sense

    before_validation :drop_unused_options
  end

  def choice_list
    if choices_setting.present?
      Settings[choices_setting.to_sym].to_s.split(",").map(&:strip).reject(&:blank?)
    else
      Array(choices)
    end
  end

  def choices_text
    Array(choices).join("\n")
  end

  def choices_text=(text)
    self.choices = text.to_s.lines.map(&:strip).reject(&:blank?)
  end

  # Stored value (JSON text) -> Ruby value.
  def cast(raw)
    return (type_boolean? ? false : nil) if raw.nil?

    value = JSON.parse(raw)
    case data_type
    when "boolean" then value == true
    when "date" then Date.iso8601(value.to_s)
    when "integer" then Integer(value)
    when "multi_select" then Array(value)
    else value.to_s
    end
  rescue JSON::ParserError, ArgumentError, TypeError
    nil
  end

  # Ruby value -> stored value (JSON text). nil means "no value".
  def serialize(value)
    return nil if value.nil?
    (value.is_a?(Date) ? value.iso8601 : value).to_json
  end

  # Form input -> [value, error]. A blank input normalizes to nil, which
  # clears the value. `current` keeps a retired choice selectable for the
  # person who already has it.
  def normalize(input, current: nil)
    case data_type
    when "boolean"
      [ ActiveModel::Type::Boolean.new.cast(input) ? true : nil, nil ]
    when "multi_select"
      values = Array(input).map { |value| value.to_s.strip }.reject(&:blank?).uniq
      return [ nil, nil ] if values.empty?
      (values - choice_list - Array(current)).any? ? [ nil, "includes a choice that isn't available" ] : [ values, nil ]
    else
      text = input.to_s.strip
      text.empty? ? [ nil, nil ] : normalize_text(text, current)
    end
  end

  private

  def normalize_text(text, current)
    case data_type
    when "string"
      matches_pattern?(text) ? [ text, nil ] : [ nil, pattern_hint.presence || "isn't in the expected format" ]
    when "text"
      [ text, nil ]
    when "date"
      date = parse_date(text)
      return [ nil, "isn't a valid date" ] unless date
      out_of_range?(date, parse_date(min), parse_date(max)) ? [ nil, range_message(min, max) ] : [ date, nil ]
    when "integer"
      number = parse_integer(text)
      return [ nil, "must be a whole number" ] unless number
      out_of_range?(number, parse_integer(min), parse_integer(max)) ? [ nil, range_message(min, max) ] : [ number, nil ]
    when "select"
      choice_list.include?(text) || text == current ? [ text, nil ] : [ nil, "isn't one of the choices" ]
    when "phone"
      PHONE_FORMAT.match?(text) ? [ text, nil ] : [ nil, "isn't a valid phone number" ]
    when "email"
      URI::MailTo::EMAIL_REGEXP.match?(text) ? [ text, nil ] : [ nil, "isn't a valid email address" ]
    end
  end

  def matches_pattern?(text)
    pattern.blank? || Regexp.new(pattern, timeout: 0.5).match?(text)
  rescue RegexpError, Regexp::TimeoutError
    false
  end

  def parse_date(value)
    Date.iso8601(value.to_s) if value.present?
  rescue Date::Error
    nil
  end

  def parse_integer(value)
    Integer(value.to_s, 10) if value.present?
  rescue ArgumentError
    nil
  end

  def out_of_range?(value, low, high)
    (low && value < low) || (high && value > high)
  end

  def range_message(low, high)
    if low.present? && high.present?
      "must be between #{low} and #{high}"
    elsif low.present?
      "must be #{low} or more"
    else
      "must be #{high} or less"
    end
  end

  def drop_unused_options
    allowed = case data_type
    when "select", "multi_select" then %w[ choices choices_setting ]
    when "integer", "date" then %w[ min max ]
    when "string" then %w[ pattern pattern_hint ]
    else []
    end
    self.options = (options || {}).slice(*allowed).reject { |_, value| value.blank? }
  end

  def options_make_sense
    case data_type
    when "select", "multi_select"
      if choices_setting.blank?
        errors.add(:choices, "can't be blank") if Array(choices).empty?
        errors.add(:choices, "can't contain duplicates") if Array(choices).uniq.size != Array(choices).size
      end
    when "integer"
      validate_range(parse_integer(min), parse_integer(max), "a whole number")
    when "date"
      validate_range(parse_date(min), parse_date(max), "a date (YYYY-MM-DD)")
    when "string"
      begin
        Regexp.new(pattern) if pattern.present?
      rescue RegexpError => e
        errors.add(:pattern, "isn't a valid regular expression (#{e.message})")
      end
    end
  end

  def validate_range(low, high, kind)
    errors.add(:min, "must be #{kind}") if min.present? && low.nil?
    errors.add(:max, "must be #{kind}") if max.present? && high.nil?
    errors.add(:max, "must be at least the minimum") if low && high && high < low
  end
end
