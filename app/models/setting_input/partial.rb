# The feature draws the field itself (partial:, rendered with f, setting and
# input locals). What it posts is stored as is, or passed through
# to_text: ->(posted, current) { text } when it posts several fields.
class SettingInput::Partial < SettingInput
  def to_partial_path
    options.fetch(:partial)
  end

  def text_from(posted, current = value)
    return super unless options[:to_text]

    posted = posted.to_unsafe_h if posted.respond_to?(:to_unsafe_h)
    posted = posted.with_indifferent_access if posted.is_a?(Hash)
    text = options[:to_text].call(posted, current).to_s
    same_text?(text, current) ? current : text
  end

  def default_label
    options[:default_label] || "See the field"
  end
end
