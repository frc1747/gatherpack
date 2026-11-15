# What one person may do in orders, worked out once and kept for the web
# request (Orders::Access.for), so policies, lists and Orders::WaitingOn ask
# about many requests without a query each.
module Orders
  class Access
    attr_reader :person

    def self.for(person)
      return new(person) if person.nil?

      Orders::Current.access[person.id] ||= new(person)
    end

    def initialize(person)
      @person = person
    end

    def admin?
      @admin ||= person&.admin? ? :yes : :no
      @admin == :yes
    end

    # Teams the person manages, and those below.
    def managed_team_ids
      @managed_team_ids ||= person.nil? ? Set.new : person.all_managed_teams.ids.to_set
    end

    def member_team_ids
      @member_team_ids ||= person.nil? ? Set.new : person.teams.ids.to_set
    end

    def relative_ids
      @relative_ids ||= person.nil? ? Set.new : person.relationships.pluck(:parent_id, :child_id).flatten.to_set - [ person.id ]
    end

    def manages?(team_id)
      admin? || managed_team_ids.include?(team_id)
    end

    # Teams reached as an approver on the step (management included).
    def approver_team_ids(step)
      @approver_team_ids ||= {}
      @approver_team_ids[step.key] ||= step.reach.team_ids(person).to_set
    end

    def approver_on?(step, team_id)
      admin? || approver_team_ids(step).include?(team_id)
    end

    # Teams reached on any approval step.
    def any_approver_team_ids
      @any_approver_team_ids ||= steps.map { |step| approver_team_ids(step) }.reduce(Set.new, :|)
    end

    def buyer_team_ids
      @buyer_team_ids ||= Orders::Config.buyers.team_ids(person).to_set
    end

    def buyer_for?(team_id)
      admin? || buyer_team_ids.include?(team_id)
    end

    # Holds a buyer grant or manages a team, so has a To buy list at all.
    def buyer?
      admin? || buyer_team_ids.any?
    end

    def funding_manager_team_ids
      @funding_manager_team_ids ||= Orders::Config.funding_managers.team_ids(person).to_set
    end

    def funding_manager_for?(team_id)
      admin? || funding_manager_team_ids.include?(team_id)
    end

    def funding_manager?
      admin? || funding_manager_team_ids.any?
    end

    def approver?
      admin? || any_approver_team_ids.any?
    end

    # The request was made by this person or a relative (any relationship
    # type), so they can't decide on it.
    def own_or_relative?(order_request)
      return false if person.nil?

      order_request.requested_by_id == person.id || relative_ids.include?(order_request.requested_by_id)
    end

    # May make requests at all (orders_requesters): everyone signed in when
    # the setting is blank, else members of its teams and the teams below.
    def requester?
      return false if person.nil?
      return @requester unless @requester.nil?

      teams = Orders::Config.requester_teams
      @requester = admin? || teams.nil? ||
        (member_team_ids & teams.flat_map { |team| [ team.id ] + team.all_descendant_ids }.to_set).any?
    end

    def steps
      @steps ||= Orders::Config.approval_steps
    end
  end
end
