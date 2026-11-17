# A picker for one setting on the settings page (registered with
# Settings.input). Each kind draws itself with the partial
# settings/inputs/_<kind> and turns what the form posts back into the text
# the setting has always stored, so the readers of a setting don't change.
#
# Saving rules shared by every kind:
# - A saved value the picker can't show (a renamed badge, a deleted team, an
#   unknown word) is shown as "Not found: <text>" and kept unless the admin
#   removes it. Nothing is dropped silently.
# - A value saved unchanged keeps its exact text (spacing, line endings).
class SettingInput
  KINDS = {
    select: "SettingInput::Select",             # choices: [[label, value], ...] or values; include_blank:
    checkboxes: "SettingInput::Checkboxes",     # choices: (or a callable), separator: ", " or "\n", normalize:
    teams: "SettingInput::Teams",               # stored one team name per line
    badge_grants: "SettingInput::BadgeGrants",  # "Badge name > Highest team name" lines; badges: (a callable scope)
    list: "SettingInput::List",                 # free entries; separator: ", " or "\n"
    text: "SettingInput::Text",                 # a text box; suggestions: (or a callable)
    date: "SettingInput::DateValue",            # YYYY-MM-DD
    month_day: "SettingInput::MonthDay",        # MM-DD
    date_or_days: "SettingInput::DateOrDays",   # YYYY-MM-DD, a number of days, or blank for never
    partial: "SettingInput::Partial"            # partial:, to_text: ->(posted, current) { text }, default_label:
  }.freeze

  attr_reader :setting, :options

  def self.class_for(kind)
    KINDS.fetch(kind.to_sym) { raise ArgumentError, "Unknown setting input kind: #{kind.inspect}" }.constantize
  end

  # The input for a setting, or nil when it's drawn as a text box.
  def self.for(setting)
    setting = Settings.get(setting.to_sym) unless setting.is_a?(Settings::Setting)
    registered = setting && Settings.input_for(setting.setting_key)
    return unless registered

    class_for(registered.kind).new(setting, registered.options)
  end

  def initialize(setting, options = {})
    @setting = setting
    @options = options
  end

  def kind
    KINDS.key(self.class.name)
  end

  def to_partial_path
    "settings/inputs/#{kind}"
  end

  def setting_key
    setting.setting_key
  end

  def value
    setting.value.to_s
  end

  # The text to store for what the form posted. A plain string is stored as
  # posted; kinds that post several fields override #text_from_fields.
  def text_from(posted, current = value)
    text =
      if posted.respond_to?(:to_unsafe_h) || posted.is_a?(Hash)
        fields = posted.respond_to?(:to_unsafe_h) ? posted.to_unsafe_h : posted
        text_from_fields(fields.with_indifferent_access, current)
      else
        posted.to_s
      end
    same_text?(text, current) ? current : text
  end

  # Whether the picker can show the saved value. When it can't, the page
  # shows the text as saved, with a note, rather than a blank picker that
  # would clear it.
  def readable?(text = value)
    true
  end

  def default_label
    options[:default_label] || describe(setting.default_value.to_s)
  end

  private

  def text_from_fields(fields, current)
    fields[:value].to_s
  end

  def describe(text)
    text.presence || "None"
  end

  # Values that differ only in spacing or line endings are the same value.
  def same_text?(text, current)
    text.to_s.strip == current.to_s.strip
  end

  def resolve(option)
    option.respond_to?(:call) ? option.call : option
  end

  # [[label, value], ...] from choices given as pairs or plain values.
  def choice_pairs(choices)
    Array(resolve(choices)).map { |choice| choice.is_a?(Array) ? [ choice[0].to_s, choice[1].to_s ] : [ choice.to_s, choice.to_s ] }
  end
end
