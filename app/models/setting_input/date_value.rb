# A date, stored as YYYY-MM-DD.
class SettingInput::DateValue < SettingInput
  def readable?(text = value)
    text.blank? || SettingInput::DateValue.parse(text).present?
  end

  def self.parse(text)
    Date.iso8601(text.to_s.strip)
  rescue Date::Error
    nil
  end

  def default_label
    options[:default_label] || describe(self.class.parse(setting.default_value)&.to_fs(:long) || setting.default_value.to_s)
  end
end
