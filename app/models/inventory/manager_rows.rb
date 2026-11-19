# The Inventory Managers rows on Inventory setup (inventory/setup/_managers):
# one row per line of the inventory_managers setting, each a "Who" (a badge,
# the managers of a team, or the managers of each team) and a "For" team.
# It reads and writes the lines Inventory::Reach parses, and keeps a line's
# exact text when its row still says the same, so opening the page and
# saving changes nothing. A line naming a badge or team that isn't found,
# or one that doesn't parse, shows as "Not found" and is kept until removed.
module Inventory
  class ManagerRows
    Row = Data.define(:line, :kind, :badge_name, :manager_team_name, :team_name, :missing)

    WHO_CHOICES = [ [ "A badge", "badge" ], [ "Managers of a team", "team_managers" ],
      [ "Managers of the item's own team", "own_team_managers" ] ].freeze
    BLANK_TEAM_LABEL = "Up to: every team".freeze

    attr_reader :text

    def initialize(text)
      @text = text.to_s
    end

    def self.lines(text)
      text.to_s.lines.map(&:strip).compact_blank
    end

    # The setting's text for what the rows posted:
    # { rows: { "0" => { line:, who:, badge:, manager_team:, team:, remove: } } }
    # in page order. A row without a Who (a "Not found" row) keeps its line;
    # a removed row, or one missing its badge or team, is dropped. Text
    # posted as is (a text box) is stored as posted.
    def self.text_from(posted, current)
      posted = posted.to_unsafe_h if posted.respond_to?(:to_unsafe_h)
      return posted.to_s unless posted.is_a?(Hash)

      rows = posted.with_indifferent_access[:rows]
      rows = rows.respond_to?(:values) ? rows.values : Array(rows)
      text = rows.filter_map { |row| line_from(row.to_h.with_indifferent_access) }.join("\n")
      lines(text) == lines(current) ? current.to_s : text
    end

    def self.line_from(row)
      return if row[:remove] == "1"
      return row[:line].to_s.strip.presence unless row.key?(:who)

      line = Inventory::Reach.format_line(row[:who], badge_name: row[:badge].presence,
        manager_team_name: row[:manager_team].presence, team_name: row[:team].presence)
      return if line.nil?

      same?(Inventory::Reach.parse_line(row[:line]), Inventory::Reach.parse_line(line)) ? row[:line].to_s.strip : line
    end

    # Badges match ignoring case, as Inventory::Reach reads them.
    def self.same?(one, other)
      return false if one.nil? || other.nil?

      one.with(badge_name: one.badge_name&.downcase) == other.with(badge_name: other.badge_name&.downcase)
    end

    def rows
      self.class.lines(text).map do |line|
        parsed = Inventory::Reach.parse_line(line)
        badge = parsed.badge_name && badge_names.find { |name| name.casecmp?(parsed.badge_name) }
        found = Inventory::Reach.new([ line ]).grants.any? || (parsed.kind == "badge" && badge && team_found?(parsed.team_name))
        if found
          Row.new(line, parsed.kind, badge, parsed.manager_team_name, parsed.team_name, false)
        else
          Row.new(line, nil, nil, nil, nil, true)
        end
      end
    end

    # Badges only admins assign, the ones a row counts.
    def badge_names
      @badge_names ||= Badge.added_by_admin.order(:name).pluck(:name)
    end

    def team_names
      @team_names ||= Team.order(:name).pluck(:name).uniq
    end

    private

    # A badge row still shows its pickers while the badges feature is off.
    def team_found?(name)
      name.nil? || team_names.include?(name)
    end
  end
end
