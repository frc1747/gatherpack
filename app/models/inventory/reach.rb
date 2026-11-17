# A delegated grant: a list of "Badge name > Team name" pairs, the same
# shape as the other badge grants (the sign-ups organizer grant among them).
# Inventory carries its own copy so it depends on none of them. A holder of
# one of the badges reaches the named team and every team below it, whatever
# teams the holder is in. With no team named, the badge reaches every team.
# A named team that doesn't exist grants nothing. Several pairs give the
# union. Only admin-assigned badges count.
#
# Admins reach every team, and managers reach the teams they manage and
# those below; #team_ids includes both, so callers needn't check them again.
module Inventory
  class Reach
    attr_reader :lines

    def initialize(lines)
      @lines = Array(lines).map(&:to_s).map(&:strip).compact_blank
    end

    # [badge, team or nil] pairs; nil reaches every team.
    def grants
      return [] unless GatherPack::Features.enabled?(:badges)

      @grants ||= lines.filter_map do |line|
        badge_name, team_name = line.split(">", 2).map(&:strip)
        next if badge_name.blank?

        badge = Badge.added_by_admin.find_by("LOWER(name) = ?", badge_name.downcase)
        next unless badge

        team = Team.find_by(name: team_name) if team_name.present?
        next if team_name.present? && team.nil?

        [ badge, team ]
      end
    end

    # The grants whose badge this person holds.
    def grants_for(person)
      return [] if person.nil? || grants.empty?

      badge_ids = BadgeAssignment.where(person_id: person.id).pluck(:badge_id)
      grants.select { |badge, _team| badge_ids.include?(badge.id) }
    end

    def holder?(person)
      grants_for(person).any?
    end

    # The people holding one of the grants' badges.
    def holders
      return Person.none if grants.empty?

      Person.where(id: BadgeAssignment.where(badge_id: grants.map { |badge, _team| badge.id }).select(:person_id))
    end

    # The teams the person's grants reach, not counting management.
    def granted_team_ids(person)
      held = grants_for(person)
      return [] if held.empty?

      held.flat_map do |_badge, team|
        team ? [ team.id ] + team.all_descendant_ids : Team.ids
      end.uniq
    end

    # Every team the person reaches: all for an admin, else the teams they
    # manage (and those below) and their grants' reach.
    def team_ids(person)
      return [] if person.nil?
      return Team.ids if person.admin?

      (person.all_managed_teams.ids + granted_team_ids(person)).uniq
    end

    def reaches?(person, team)
      return false if person.nil? || team.nil?

      team_ids(person).include?(team.respond_to?(:id) ? team.id : team)
    end
  end
end
