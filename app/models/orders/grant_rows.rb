# The grant rows of an orders role setting (orders_buyers,
# orders_funding_managers) as Orders setup draws them: a row per saved line
# with a "Who" (a badge, the managers of a team, or the managers of the
# request's own team) and a "For" team. It turns what the form posts back
# into the lines Orders::Reach reads. A saved line whose badge or team isn't
# found shows as "Not found" and is kept until removed; a line saved
# unchanged keeps its exact text.
module Orders
  class GrantRows
    Row = Data.define(:line, :kind, :badge_name, :manager_team_name, :team_name, :missing)

    # The "Who" choices, as [label, kind].
    WHO_CHOICES = [
      [ "A badge", "badge" ],
      [ "Managers of a team", "team_managers" ],
      [ "Managers of the request's own team", "own_team_managers" ]
    ].freeze

    attr_reader :text

    def initialize(text)
      @text = text.to_s
    end

    # Badges admins assign: the only ones that count.
    def badges
      Badge.added_by_admin.order(:name).to_a
    end

    def badge_names
      @badge_names ||= badges.map(&:name)
    end

    def team_names
      @team_names ||= Team.order(:name).pluck(:name)
    end

    def rows
      Orders::Config.grant_lines(text).map do |line|
        kind, who, team_name = Orders::Reach.parse_line(line)
        badge = kind == :badge ? badge_names.find { |name| name.casecmp?(who) } : nil
        manager_team = kind == :team_managers && team_names.include?(who) ? who : nil
        found = case kind
        when :own_team_managers then true
        when :team_managers then manager_team.present?
        else badge.present?
        end
        found &&= team_name.nil? || kind == :own_team_managers || team_names.include?(team_name)
        if found
          Row.new(line, kind, badge, manager_team, kind == :own_team_managers ? nil : team_name, false)
        else
          Row.new(line, nil, nil, nil, nil, true)
        end
      end
    end

    # Rows come as { "0" => { line:, kind:, badge:, manager_team:, team:,
    # remove: } } in page order. A row with a "Who" is saved from its
    # pickers, or keeps its line when they still say the same; a "Not found"
    # row (no "Who") keeps its line. A removed row, or one whose "Who" is
    # missing its badge or team, is dropped. A plain string is the text
    # itself. Text that says the same as current gives current.
    def self.text_from(posted, current)
      posted = posted.to_unsafe_h if posted.respond_to?(:to_unsafe_h)
      text = posted.is_a?(Hash) ? text_from_rows(posted.with_indifferent_access[:rows]) : posted.to_s
      Orders::Config.grant_lines(text) == Orders::Config.grant_lines(current) ? current.to_s : text
    end

    def self.text_from_rows(rows)
      rows = rows.respond_to?(:values) ? rows.values : Array(rows)
      rows.filter_map do |row|
        row = row.with_indifferent_access
        next if row[:remove] == "1"
        next row[:line].to_s.strip.presence unless row.key?(:kind)

        line = line_from(row)
        next if line.nil?

        original = row[:line].to_s.strip
        original.present? && Orders::Reach.parse_line(original)&.then { |parsed| same_row?(parsed, Orders::Reach.parse_line(line)) } ? original : line
      end.join("\n")
    end

    def self.line_from(row)
      case row[:kind].to_s
      when "own_team_managers"
        Orders::Reach.format_line(:own_team_managers, nil)
      when "team_managers"
        row[:manager_team].presence && Orders::Reach.format_line(:team_managers, row[:manager_team], row[:team].presence)
      when "badge"
        row[:badge].presence && Orders::Reach.format_line(:badge, row[:badge], row[:team].presence)
      end
    end

    # Badge names match ignoring case, as Orders::Reach reads them.
    def self.same_row?(one, other)
      return false if one.nil? || other.nil? || one[0] != other[0] || one[2] != other[2]

      one[0] == :badge ? one[1].to_s.casecmp?(other[1].to_s) : one[1] == other[1]
    end
  end
end
