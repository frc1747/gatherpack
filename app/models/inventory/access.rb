# What one person may do in inventory, worked out once and kept for the web
# request (Inventory::Access.for), so policies and lists ask about many
# items without a query each.
#
# Spec §3.6: a team's items and locations are visible to everyone in
# person.all_team_ids of that team (their teams, those above, and those
# below the ones they manage), when they may use inventory at all
# (inventory_users). Inventory managers (the inventory_managers grant), team
# managers and admins also see and manage everything within their reach.
module Inventory
  class Access
    attr_reader :person

    def self.for(person)
      return new(person) if person.nil?

      Inventory::Current.access[person.id] ||= new(person)
    end

    def initialize(person)
      @person = person
    end

    def admin?
      @admin ||= person&.admin? ? :yes : :no
      @admin == :yes
    end

    # Teams whose inventory the person manages: all for an admin, the teams
    # they manage and those below, and their inventory_managers grants.
    def managed_team_ids
      @managed_team_ids ||= person.nil? ? Set.new : Inventory::Config.managers.team_ids(person).to_set
    end

    def manages?(team_id)
      admin? || managed_team_ids.include?(team_id)
    end

    # Manages any team's inventory: sees Reorder, Items, Places and Changes.
    def manager?
      admin? || managed_team_ids.any?
    end

    # May use inventory at all (inventory_users): everyone signed in when
    # the setting is blank, else members of its teams and the teams below.
    # Inventory managers always may.
    def user?
      return false if person.nil?
      return @user unless @user.nil?

      teams = Inventory::Config.user_teams
      @user = manager? || teams.nil? ||
        (person.teams.ids.to_set & teams.flat_map { |team| [ team.id ] + team.all_descendant_ids }.to_set).any?
    end

    # Teams whose items and locations the person sees.
    def visible_team_ids
      @visible_team_ids ||=
        if person.nil?
          Set.new
        elsif admin?
          Team.ids.to_set
        else
          member = user? ? person.all_teams.ids : []
          (member.to_set | managed_team_ids)
        end
    end

    def sees_team?(team_id)
      admin? || visible_team_ids.include?(team_id)
    end

    def sees?(record)
      !record.nil? && sees_team?(record.team_id)
    end

    def member_kinds
      @member_kinds ||= Inventory::Config.member_kinds
    end

    def member_unit_actions
      @member_unit_actions ||= Inventory::Config.member_unit_actions
    end

    # May record this kind of movement of the item at the location (and
    # to_location for a move): sees them all, and either the kind is a
    # member's kind or the person manages the item's team.
    def may_record?(kind, item, location, to_location = nil)
      return false if person.nil? || item.nil? || location.nil?
      return false unless sees?(item) && sees?(location) && (to_location.nil? || sees?(to_location))

      manages?(item.team_id) || (user? && member_kinds.include?(kind.to_s))
    end

    # May take this action on the unit (and into a target location or unit).
    def may_unit_action?(action, unit, target = nil)
      return false if person.nil? || unit.nil?
      return false unless sees?(unit.item) && sees?(unit.location)
      return false if target && !sees?(target.is_a?(ItemUnit) ? target.location : target)

      manages?(unit.item.team_id) || (user? && member_unit_actions.include?(action.to_s))
    end
  end
end
