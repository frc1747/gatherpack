# One of a fixed set of choices, matched ignoring case. A saved value that
# isn't one of them is offered as "Not found: <value>", and a blank one as
# "Not set", and either stays selected until changed, so saving the page
# never swaps in the first choice.
class SettingInput::Select < SettingInput
  def choices
    pairs = choice_pairs(options[:choices])
    return pairs if selected_value.present? && pairs.any? { |_, choice| choice == selected_value }
    return pairs if value.blank? && include_blank

    pairs + [ value.blank? ? [ "Not set", "" ] : [ "Not found: #{value}", value ] ]
  end

  # The choice matching the saved value, as the choice spells it.
  def selected_value
    choice_pairs(options[:choices]).find { |_, choice| choice.casecmp?(value.strip) }&.last || value
  end

  def include_blank
    options.fetch(:include_blank, false)
  end

  def default_label
    default = setting.default_value.to_s
    options[:default_label] || describe(choice_pairs(options[:choices]).find { |_, choice| choice.casecmp?(default) }&.first || default)
  end

  private

  def same_text?(text, current)
    text.to_s.strip.casecmp?(current.to_s.strip)
  end
end
