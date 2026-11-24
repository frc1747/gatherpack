# Badge grants: one "Badge name > Highest team name" (or "Badge name" alone)
# per line, the format the organizer and buyer settings read. Each line is a
# row with a badge and an optional highest team. A line whose badge or team
# isn't found shows as "Not found" and is kept until removed.
#
# SettingInput::BadgeGrants.parse_line and .format_line are the one place the
# line format is read and written; readers of these settings can use them so
# the picker and the readers can't drift apart.
class SettingInput::BadgeGrants < SettingInput
  Row = Data.define(:line, :badge_name, :team_name, :missing)

  SEPARATOR = ">".freeze

  # [badge name, team name or nil] for one line, or nil for a blank one.
  def self.parse_line(line)
    badge_name, team_name = line.to_s.split(SEPARATOR, 2).map(&:strip)
    return if badge_name.blank?

    [ badge_name, team_name.presence ]
  end

  def self.format_line(badge_name, team_name = nil)
    team_name.present? ? "#{badge_name} #{SEPARATOR} #{team_name}" : badge_name.to_s
  end

  def self.lines(text)
    text.to_s.lines.map(&:strip).compact_blank
  end

  # The badges offered, by name. A feature that only counts some badges (say,
  # those only admins assign) passes badges: -> { Badge.where(...) }.
  def badges
    scope = options[:badges] ? resolve(options[:badges]) : Badge.all
    scope.order(:name).to_a
  end

  def teams
    SettingInput::Teams.new(setting).choices
  end

  # A row per saved line, with the badge and team names as the pickers know
  # them (badges match ignoring case, teams exactly, as the readers do).
  def rows
    badge_names = badges.map(&:name)
    team_names = teams.map(&:last)

    self.class.lines(value).map do |line|
      badge_name, team_name = self.class.parse_line(line)
      badge = badge_names.find { |name| name.casecmp?(badge_name) }
      if badge && (team_name.nil? || team_names.include?(team_name))
        Row.new(line, badge, team_name, false)
      else
        Row.new(line, nil, nil, true)
      end
    end
  end

  private

  # Rows come as { "0" => { line:, badge:, team:, remove: } } in page order.
  # A row with a badge picker is saved from its pickers, or keeps its line
  # when they still say the same; a "Not found" row (no badge picker) keeps
  # its line. A removed row or one with no badge is dropped.
  def text_from_fields(fields, current)
    rows = fields[:rows].respond_to?(:values) ? fields[:rows].values : Array(fields[:rows])
    rows.filter_map do |row|
      row = row.with_indifferent_access
      next if row[:remove] == "1"
      next row[:line].to_s.strip.presence unless row.key?(:badge)
      next if row[:badge].blank?

      original = self.class.parse_line(row[:line])
      same = original && original[0].casecmp?(row[:badge]) && original[1] == row[:team].presence
      same ? row[:line].to_s.strip : self.class.format_line(row[:badge], row[:team])
    end.join("\n")
  end

  def same_text?(text, current)
    self.class.lines(text) == self.class.lines(current)
  end
end
