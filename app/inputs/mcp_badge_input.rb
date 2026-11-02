# Settings input for Mcp::Access's allowed badge: a select of badges by name
# that stores the badge's neat ID. Used through the :mcp_badge setting type
# (the settings page passes as: setting_type).
class McpBadgeInput < SimpleForm::Inputs::Base
  BLANK_LABEL = "Every member".freeze
  MISSING_LABEL = "Missing badge (no one can connect)".freeze
  SPECIAL_LABELS = [ BLANK_LABEL, MISSING_LABEL ].freeze
  # Badges members can give themselves; picking one makes the limit self-service.
  SELF_SERVICE = %w[added_by_current_member added_by_manager_or_self added_by_admin_or_self has_account].freeze
  SELF_SERVICE_NOTE = "members can give this to themselves".freeze

  def input(wrapper_options = nil)
    options = merge_wrapper_options(input_html_options, wrapper_options)
    options.delete(:value)
    options.delete(:placeholder)
    # Read from the store, as Mcp::Access does: this process's copy can be stale.
    stored = Mcp::Access.stored_setting(attribute_name).strip
    @builder.select(attribute_name, choices(stored), { selected: stored }, options)
  end

  private

  # A stored value that names no badge locks everyone out (Mcp::Access), so
  # it gets its own selected option instead of falling back to the blank one.
  def choices(stored)
    badges = Badge.includes(:team).order(:name).to_a.select { |badge| offered?(badge, stored) }
    list = [ [ BLANK_LABEL, "" ] ]
    list << [ MISSING_LABEL, stored ] if stored.present? && badges.none? { |badge| badge.neat_id == stored }
    list + badges.zip(labels_for(badges)).map { |badge, label| [ label, badge.neat_id ] }
  end

  # Self-service badges are left out, unless one is already the stored value.
  def offered?(badge, stored)
    SELF_SERVICE.exclude?(badge.permission) || badge.neat_id == stored
  end

  # Names are shown as written, so a badge can't pass for a special option,
  # and two badges never read alike.
  def labels_for(badges)
    labels = badges.map { |badge| special?(badge) ? "#{badge.name} (badge, #{team_name(badge)})" : badge.name }
    labels = disambiguate(badges, labels) { |badge| team_name(badge) }
    labels = disambiguate(badges, labels, &:short)
    labels = disambiguate(badges, labels, &:neat_id)
    badges.zip(labels).map do |badge, label|
      SELF_SERVICE.include?(badge.permission) ? "#{label} (#{SELF_SERVICE_NOTE})" : label
    end
  end

  # Adds the block's detail to every label that still appears more than once.
  def disambiguate(badges, labels)
    repeated = labels.tally.select { |_, count| count > 1 }.keys
    badges.zip(labels).map { |badge, label| repeated.include?(label) ? "#{label} (#{yield(badge)})" : label }
  end

  def special?(badge)
    SPECIAL_LABELS.any? { |label| badge.name.squish.casecmp?(label) }
  end

  def team_name(badge)
    badge.team&.name || "no team"
  end
end
