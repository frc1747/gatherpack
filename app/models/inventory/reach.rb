# A delegated grant: a list of "Badge name > Highest team name" pairs, the
# same shape as the other badge → highest-team grants (the sign-ups
# organizer grant among them), so they can later be merged without changing
# behavior. Inventory carries its own copy so it depends on none of them. A holder of one of the
# badges reaches the teams they belong to (their own and those above) at or
# below the pair's highest team, plus the teams below their own. Leaving
# out the highest team allows only the teams they're directly in and those
# below. Several pairs give the union. Only admin-assigned badges count.
#
# Admins reach every team, and managers reach the teams they manage and
# those below; #team_ids includes both, so callers needn't check them again.
module Inventory
  class Reach
    attr_reader :lines

    def initialize(lines)
      @lines = Array(lines).map(&:to_s).map(&:strip).compact_blank
    end

    # [badge, highest team or nil] pairs.
    def grants
      return [] unless GatherPack::Features.enabled?(:badges)

      @grants ||= lines.filter_map do |line|
        badge_name, team_name = line.split(">", 2).map(&:strip)
        next if badge_name.blank?

        badge = Badge.added_by_admin.find_by("LOWER(name) = ?", badge_name.downcase)
        next unless badge

        [ badge, team_name.present? ? Team.find_by(name: team_name) : nil ]
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

      direct = person.teams.ids
      below = (direct + Team.where(id: direct).flat_map(&:all_descendant_ids)).uniq
      above = person.all_ancestor_teams.ids

      held.flat_map do |_badge, cap|
        next below unless cap

        within = [ cap.id ] + cap.all_descendant_ids
        (above + below) & within
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
