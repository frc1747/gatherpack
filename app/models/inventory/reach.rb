# Who manages inventory, and for which teams: a list of grant rows, read as
# "any of these", one per line of the inventory_managers setting:
#
#   Badge name > Team name              holders of the badge, for that team and those below
#   Badge name                          holders of the badge, for every team
#   Managers of Team name > Team name   the first team's own managers (not those of a team
#                                       above or below it), for the second and those below
#   Managers of Team name               the same, for every team
#   Managers of each team               managers of a team or a team above it, for that team
#
# Inventory carries its own copy of this grammar so it depends on no other
# feature. A line naming a badge or team that doesn't exist, or one that
# doesn't parse, grants nothing. Only admin-assigned badges count. Team
# managers manage inventory only through a row that says so; admins reach
# every team whatever the rows say.
module Inventory
  class Reach
    KINDS = %w[badge team_managers own_team_managers].freeze
    MANAGERS_OF = /\Amanagers of\s+/i
    EACH_TEAM = "each team".freeze
    SEPARATOR = ">".freeze

    # One line as written: kind, the badge or managers' team named, and the
    # team it's for (nil for every team, or the manager's own teams).
    Line = Data.define(:kind, :badge_name, :manager_team_name, :team_name)

    # One line looked up: badge or manager_team is the who, team the for.
    Grant = Data.define(:kind, :badge, :manager_team, :team)

    attr_reader :lines

    def initialize(lines)
      @lines = Array(lines).map(&:to_s).map(&:strip).compact_blank
    end

    # The Line for one line of text, or nil for a blank one.
    def self.parse_line(text)
      text = text.to_s.strip
      return if text.blank?

      if text.match?(MANAGERS_OF)
        who, team_name = text.sub(MANAGERS_OF, "").split(SEPARATOR, 2).map(&:strip)
        if who.casecmp?(EACH_TEAM)
          Line.new("own_team_managers", nil, nil, team_name.presence)
        else
          Line.new("team_managers", nil, who.presence, team_name.presence)
        end
      else
        badge_name, team_name = text.split(SEPARATOR, 2).map(&:strip)
        Line.new("badge", badge_name.presence, nil, team_name.presence)
      end
    end

    # The text for a row, or nil when it doesn't name what its kind needs.
    def self.format_line(kind, badge_name: nil, manager_team_name: nil, team_name: nil)
      for_team = team_name.present? ? " #{SEPARATOR} #{team_name}" : ""
      case kind.to_s
      when "badge" then "#{badge_name}#{for_team}" if badge_name.present?
      when "team_managers" then "Managers of #{manager_team_name}#{for_team}" if manager_team_name.present?
      when "own_team_managers" then "Managers of #{EACH_TEAM}"
      end
    end

    # The rows that name things that exist, looked up once.
    def grants
      @grants ||= lines.filter_map { |text| grant_for(self.class.parse_line(text)) }
    end

    # The grants that apply to this person.
    def grants_for(person)
      return [] if person.nil? || grants.empty?

      grants.select { |grant| holds?(person, grant) }
    end

    def holder?(person)
      grants_for(person).any?
    end

    # The people one of the rows applies to.
    def holders
      ids = grants.flat_map do |grant|
        case grant.kind
        when "badge" then BadgeAssignment.where(badge_id: grant.badge.id).pluck(:person_id)
        when "team_managers" then Membership.where(manager: true, team_id: grant.manager_team.id).pluck(:person_id)
        else Membership.where(manager: true).pluck(:person_id)
        end
      end
      ids.empty? ? Person.none : Person.where(id: ids.uniq)
    end

    # The teams the person's rows reach, not counting being an admin.
    def granted_team_ids(person)
      held = grants_for(person)
      return [] if held.empty?

      held.flat_map do |grant|
        if grant.kind == "own_team_managers"
          managed_team_ids(person)
        elsif grant.team
          [ grant.team.id ] + grant.team.all_descendant_ids
        else
          Team.ids
        end
      end.uniq
    end

    # Every team the person reaches: all for an admin, else their rows' reach.
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

    def grant_for(line)
      return if line.nil?

      team = line.team_name && Team.find_by(name: line.team_name)
      return if line.team_name && team.nil?

      case line.kind
      when "badge"
        return unless line.badge_name && GatherPack::Features.enabled?(:badges)

        badge = Badge.added_by_admin.find_by("LOWER(name) = ?", line.badge_name.downcase)
        Grant.new("badge", badge, nil, team) if badge
      when "team_managers"
        manager_team = Team.find_by(name: line.manager_team_name)
        Grant.new("team_managers", nil, manager_team, team) if manager_team
      when "own_team_managers"
        Grant.new("own_team_managers", nil, nil, nil) if line.team_name.nil?
      end
    end

    def holds?(person, grant)
      case grant.kind
      when "badge" then held_badge_ids(person).include?(grant.badge.id)
      when "team_managers" then direct_team_ids(person).include?(grant.manager_team.id)
      else managed_team_ids(person).any?
      end
    end

    def held_badge_ids(person)
      @held_badge_ids ||= {}
      @held_badge_ids[person.id] ||= BadgeAssignment.where(person_id: person.id).pluck(:badge_id)
    end

    # The teams the person is a manager of themselves.
    def direct_team_ids(person)
      @direct_team_ids ||= {}
      @direct_team_ids[person.id] ||= Membership.where(person_id: person.id, manager: true).pluck(:team_id)
    end

    # The teams the person manages and those below, from their memberships
    # (an admin isn't a manager of every team here).
    def managed_team_ids(person)
      @managed_team_ids ||= {}
      @managed_team_ids[person.id] ||= begin
        direct = direct_team_ids(person)
        direct + Team.where(id: direct).flat_map(&:all_descendant_ids)
      end
    end
  end
end
