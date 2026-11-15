# One of a fixed set of choices. A saved value that isn't one of them is
# offered as "Not found: <value>" and stays selected until changed.
class SettingInput::Select < SettingInput
  def choices
    pairs = choice_pairs(options[:choices])
    return pairs if value.blank? || pairs.any? { |_, choice| choice == value }

    pairs + [ [ "Not found: #{value}", value ] ]
  end

  def include_blank
    options.fetch(:include_blank, false)
  end

  def default_label
    options[:default_label] || describe(choice_pairs(options[:choices]).find { |_, choice| choice == setting.default_value.to_s }&.first || setting.default_value.to_s)
  end
end
