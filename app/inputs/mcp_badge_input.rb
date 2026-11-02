# Settings input for Mcp::Access's allowed badge: a select of badges by name
# that stores the badge's neat ID. Used through the :mcp_badge setting type
# (the settings page passes as: setting_type).
class McpBadgeInput < SimpleForm::Inputs::Base
  BLANK_LABEL = "Every member".freeze
  MISSING_LABEL = "Missing badge (no one can connect)".freeze

  def input(wrapper_options = nil)
    options = merge_wrapper_options(input_html_options, wrapper_options)
    stored = options.delete(:value).to_s.strip
    options.delete(:placeholder)
    @builder.select(attribute_name, choices(stored), { selected: stored }, options)
  end

  private

  # A stored value that names no badge locks everyone out (Mcp::Access), so
  # it gets its own selected option instead of falling back to the blank one.
  def choices(stored)
    badges = Badge.includes(:team).order(:name).to_a
    names = badges.map(&:name).tally
    list = [ [ BLANK_LABEL, "" ] ]
    list << [ MISSING_LABEL, stored ] if stored.present? && badges.none? { |badge| badge.neat_id == stored }
    list + badges.map { |badge| [ label_for(badge, names[badge.name] > 1), badge.neat_id ] }
  end

  def label_for(badge, duplicate)
    return badge.name unless duplicate

    "#{badge.name} (#{badge.team&.name || 'no team'})"
  end
end
