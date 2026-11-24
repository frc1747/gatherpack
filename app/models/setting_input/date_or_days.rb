# Never (blank), a date (YYYY-MM-DD), or a number of days (digits), as in
# settings that act on records some time after they end.
class SettingInput::DateOrDays < SettingInput
  def mode
    return "never" if value.blank?

    value.strip.match?(/\A\d+\z/) ? "days" : "date"
  end

  def date
    value.strip if mode == "date"
  end

  def days
    value.strip if mode == "days"
  end

  def readable?(text = value)
    text.blank? || text.strip.match?(/\A\d+\z/) || SettingInput::DateValue.parse(text).present?
  end

  def default_label
    return options[:default_label] if options[:default_label]

    text = setting.default_value.to_s.strip
    return "Never" if text.blank?

    text.match?(/\A\d+\z/) ? "#{text} days after" : text
  end

  private

  def text_from_fields(fields, current)
    case fields[:mode]
    when "date" then fields[:date].to_s.strip
    when "days" then fields[:days].to_s.strip.then { |days| days.match?(/\A\d+\z/) ? days.to_i.to_s : "" }
    else ""
    end
  end
end
