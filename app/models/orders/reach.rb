# Who holds an orders role, and for which teams: a list of grant rows, read
# as "any of these". A row names who:
#
# - holders of a badge ("Badge name"), only badges admins assign;
# - the managers of a team ("Managers of Team name"): only that team's own
#   managers, not those of the teams above or below it;
# - the managers of the request's own team ("Managers of each team"), who
#   reach the teams they manage and those below (so managers of a team
#   above the request's count).
#
# and for which teams: "> Team name" reaches that team and every team below
# it; leaving it out reaches every team. A row for the request's own team
# takes no team. A named team that doesn't exist (renamed or deleted)
# reaches nothing, never every team; a line that doesn't read grants
# nothing.
#
# Buyers and funding managers each have a Reach from their setting's lines;
# an approval step has one from its approver rows (.from_rows). Admins reach
# every team; managing a team reaches nothing without a row that says so.
module Orders
  class Reach
    # kind: :badge, :team_managers or :own_team_managers. badge for :badge,
    # manager_team for :team_managers; team nil for every team.
    Row = Data.define(:kind, :badge, :manager_team, :team)

    KINDS = %i[badge team_managers own_team_managers].freeze
    SEPARATOR = ">".freeze
    MANAGERS_PREFIX = "Managers of ".freeze
    OWN_TEAM_LINE = "Managers of each team".freeze

    attr_reader :lines

    # given: Rows already looked up, in place of lines.
    def initialize(lines, given: nil)
      @lines = Array(lines).map(&:to_s).map(&:strip).compact_blank
      @given = given&.to_a
    end

    def self.from_rows(rows)
      new([], given: rows)
    end

    # [kind, who (badge or team name, nil for own team), team name or nil]
    # for one line, or nil for a blank one.
    def self.parse_line(line)
      who, team_name = line.to_s.split(SEPARATOR, 2).map(&:strip)
      return if who.blank?
      return [ :own_team_managers, nil, nil ] if who.casecmp?(OWN_TEAM_LINE)

      if who.downcase.start_with?(MANAGERS_PREFIX.downcase)
        manager_team_name = who[MANAGERS_PREFIX.length..].strip
        return [ :team_managers, manager_team_name.presence, team_name.presence ]
      end

      [ :badge, who, team_name.presence ]
    end

    # The line for a row: "Badge > Team", "Managers of Team > Team" or
    # "Managers of each team"; the team left out for every team.
    def self.format_line(kind, who, team_name = nil)
      head =
        case kind.to_sym
        when :own_team_managers then return OWN_TEAM_LINE
        when :team_managers then "#{MANAGERS_PREFIX}#{who}"
        else who.to_s
        end
      team_name.present? ? "#{head} #{SEPARATOR} #{team_name}" : head
    end

    # The rows that read, with their badges and teams looked up. A line
    # naming a badge or team that isn't found is left out.
    def rows
      return @rows ||= @given.select { |row| usable?(row) } if @given

      @rows ||= lines.filter_map { |line| row_from(line) }
    end

    # [badge, team or nil for every team] pairs: the badge rows.
    def grants
      rows.select { |row| row.kind == :badge }.map { |row| [ row.badge, row.team ] }
    end

    # The badge rows whose badge this person holds, as [badge, team] pairs.
    def grants_for(person)
      return [] if person.nil? || grants.empty?

      badge_ids = BadgeAssignment.where(person_id: person.id).pluck(:badge_id)
      grants.select { |badge, _team| badge_ids.include?(badge.id) }
    end

    # Whether a row reaches any team for this person, not counting admin.
    def holder?(person)
      granted_team_ids(person).any?
    end

    # The teams the person's rows reach, not counting admin.
    def granted_team_ids(person)
      return [] if person.nil? || rows.empty?

      managed = nil
      managed_ids = -> { managed ||= person.all_managed_teams.ids.to_set }
      direct = nil
      directly_managed_ids = -> { direct ||= person.memberships.where(manager: true).pluck(:team_id).to_set }
      held = grants_for(person).map(&:first).to_set
      reached = rows.select do |row|
        case row.kind
        when :badge then held.include?(row.badge)
        when :team_managers then directly_managed_ids.call.include?(row.manager_team.id)
        when :own_team_managers then managed_ids.call.any?
        end
      end
      return Team.ids if reached.any? { |row| row.kind != :own_team_managers && row.team.nil? }

      reached.flat_map { |row| row.kind == :own_team_managers ? managed_ids.call.to_a : subtree_ids(row.team).to_a }.uniq
    end

    # Every team the person reaches: all for an admin, else their rows'.
    def team_ids(person)
      return [] if person.nil?
      return Team.ids if person.admin?

      granted_team_ids(person)
    end

    def reaches?(person, team)
      return false if person.nil? || team.nil?

      team_ids(person).include?(team.respond_to?(:id) ? team.id : team)
    end

    private

    def row_from(line)
      kind, who, team_name = self.class.parse_line(line)
      return if kind.nil?
      return Row.new(kind: kind, badge: nil, manager_team: nil, team: nil) if kind == :own_team_managers

      team = team_name.present? ? Team.find_by(name: team_name) : nil
      return if team_name.present? && team.nil?

      case kind
      when :team_managers
        manager_team = who.present? ? Team.find_by(name: who) : nil
        manager_team && Row.new(kind: kind, badge: nil, manager_team: manager_team, team: team)
      else
        return unless GatherPack::Features.enabled?(:badges)

        badge = Badge.added_by_admin.find_by("LOWER(name) = ?", who.downcase)
        badge && Row.new(kind: kind, badge: badge, manager_team: nil, team: team)
      end
    end

    def usable?(row)
      case row.kind
      when :badge then GatherPack::Features.enabled?(:badges) && row.badge&.added_by_admin?
      when :team_managers then row.manager_team.present?
      else true
      end
    end

    def subtree_ids(team)
      @subtree_ids ||= {}
      @subtree_ids[team.id] ||= [ team.id, *team.all_descendant_ids ].to_set
    end
  end
end
