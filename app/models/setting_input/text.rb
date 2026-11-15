# A text box that suggests values (suggestions: a list or a callable) but
# takes any.
class SettingInput::Text < SettingInput
  def suggestions
    Array(resolve(options[:suggestions])).map(&:to_s)
  end
end
