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

    # Sees a request as more than its requester, follower or team member:
    # manages its team, or reaches it as an approver or buyer.
    def staff_for?(team_id)
      manages?(team_id) || any_approver_team_ids.include?(team_id) || buyer_for?(team_id)
    end

    # May choose a request's funding source: its team's managers until it's
    # finished, an approver who can decide it now, and its requester while
    # it's editable when orders_requesters_pick_funding is on.
    def sets_funding?(order_request)
      return false if person.nil?
      return true if manages?(order_request.team_id) && !order_request.finished?
      return true if order_request.can_decide?(person)

      order_request.requested_by_id == person.id && order_request.editable? && Orders::Config.requesters_pick_funding?
    end

    # Estimated shipping is hidden from requesters (spec §3.16).
    def sees_estimated_shipping?(order_request)
      person.present? && staff_for?(order_request.team_id)
    end

    # The teams a person may make a request for: those they're on and those
    # they manage (all for an admin).
    def request_team_ids
      @request_team_ids ||= admin? ? nil : member_team_ids | managed_team_ids
    end

    def may_request_for?(team_id)
      !person.nil? && (request_team_ids.nil? || request_team_ids.include?(team_id))
    end

    # May make requests at all (orders_requesters): everyone signed in when
    # the setting is blank, else members of its teams and the teams below.
    def requester?
      return false if person.nil?
      return @requester unless @requester.nil?

      teams = Orders::Config.requester_teams
      @requester = admin? || teams.nil? || member_of_any?(teams)
    end

    # Sees every request that isn't a draft (orders_viewers), read only:
    # members of its teams and the teams below, as for orders_requesters.
    def sees_every_request?
      return false if person.nil?
      return @sees_every_request unless @sees_every_request.nil?

      teams = Orders::Config.viewer_teams
      @sees_every_request = teams.any? && member_of_any?(teams)
    end

    def member_of_any?(teams)
      (member_team_ids & teams.flat_map { |team| [ team.id ] + team.all_descendant_ids }.to_set).any?
    end

    def steps
      @steps ||= Orders::Config.approval_steps
    end
  end
end
