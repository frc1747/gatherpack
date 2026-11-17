# Free entries, one text box each, stored joined by the separator (", " by
# default, "\n" for one per line).
class SettingInput::List < SettingInput
  def separator
    options.fetch(:separator, ", ")
  end

  def items(text = value)
    pattern = separator.strip.empty? ? /\r?\n/ : separator.strip
    text.to_s.split(pattern).map(&:strip).compact_blank
  end

  def default_label
    options[:default_label] || describe(items(setting.default_value).join(", "))
  end

  private

  def text_from_fields(fields, current)
    Array(fields[:items]).map(&:to_s).map(&:strip).compact_blank.join(separator)
  end

  def same_text?(text, current)
    items(text) == items(current)
  end
end
