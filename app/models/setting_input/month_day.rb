# A day of the year (month and day), stored as MM-DD.
class SettingInput::MonthDay < SettingInput
  # [month, day] or nil.
  def self.parse(text)
    month, day = text.to_s.strip.split("-", 2).map { |part| Integer(part, 10) }
    [ month, day ] if month.between?(1, 12) && day.to_i.between?(1, 31)
  rescue ArgumentError, TypeError, NoMethodError
    nil
  end

  def month
    self.class.parse(value)&.first
  end

  def day
    self.class.parse(value)&.last
  end

  def readable?(text = value)
    text.blank? || self.class.parse(text).present?
  end

  def default_label
    return options[:default_label] if options[:default_label]

    month, day = self.class.parse(setting.default_value)
    describe(month ? "#{Date::MONTHNAMES[month]} #{day}" : setting.default_value.to_s)
  end

  private

  # Blank unless both are picked.
  def text_from_fields(fields, current)
    month = fields[:month].presence
    day = fields[:day].presence
    return "" unless month && day

    format("%02d-%02d", month.to_i, day.to_i)
  end
end
