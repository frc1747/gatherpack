# Several fixed choices, stored as the text the setting has always used: the
# chosen values joined by the separator (", " by default, "\n" for one per
# line). Values are matched ignoring case unless normalize: says otherwise.
class SettingInput::Checkboxes < SettingInput
  Entry = Data.define(:label, :value, :checked, :missing)

  def separator
    options.fetch(:separator, ", ")
  end

  def choices
    choice_pairs(options[:choices])
  end

  # The saved values, in their saved order.
  def tokens(text = value)
    pattern = separator.strip.empty? ? /\r?\n/ : separator.strip
    text.to_s.split(pattern).map(&:strip).compact_blank
  end

  # The choices to draw, then a checked "Not found" entry for each saved
  # value that isn't one of them.
  def entries
    saved = tokens.map { |token| normalize(token) }
    known = choices.map { |label, choice| Entry.new(label, choice, saved.include?(normalize(choice)), false) }
    known_values = choices.map { |_, choice| normalize(choice) }
    missing = tokens.reject { |token| known_values.include?(normalize(token)) }.uniq { |token| normalize(token) }
    known + missing.map { |token| Entry.new("Not found: #{token}", token, true, true) }
  end

  def default_label
    return options[:default_label] if options[:default_label]

    labels = choices.to_h { |label, choice| [ normalize(choice), label ] }
    describe(tokens(setting.default_value).map { |token| labels.fetch(normalize(token), token) }.join(", "))
  end

  private

  # Saved values still chosen keep their text and order; new ones follow in
  # the order drawn.
  def text_from_fields(fields, current)
    chosen = Array(fields[:values]).map(&:to_s).map(&:strip).compact_blank
    wanted = chosen.map { |choice| normalize(choice) }
    kept = tokens(current).select { |token| wanted.include?(normalize(token)) }
    added = chosen.reject { |choice| kept.any? { |token| normalize(token) == normalize(choice) } }
    (kept + added).uniq { |token| normalize(token) }.join(separator)
  end

  def same_text?(text, current)
    tokens(text) == tokens(current)
  end

  def normalize(token)
    rule = options.fetch(:normalize) { ->(text) { text.downcase } }
    rule.call(token.to_s.strip)
  end
end
