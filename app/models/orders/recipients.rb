# Who hears about a request (spec §3.11). Approvers and buyers are found
# from the settings' grants the same way the pages decide who may act, so a
# notice reaches exactly the people who have the item on their list.
module Orders
  module Recipients
    module_function

    # Everyone who may decide the step on the request: not its requester or
    # their relatives, who can't decide it.
    def approvers(order_request, step)
      return [] if step.nil?

      candidates(step.reach).select do |person|
        access = Orders::Access.new(person)
        access.approver_on?(step, order_request.team_id) && !access.own_or_relative?(order_request)
      end
    end

    # Buyers whose reach includes the team, except those who chose no buying notices.
    def buyers(team_id)
      candidates(Orders::Config.buyers).select do |person|
        Orders::Access.new(person).buyer_for?(team_id) && !OrderNoticePreference.for(person).buyer_off?
      end
    end

    # The requester and the people following the request.
    def requester_and_watchers(order_request)
      [ order_request.requested_by, *order_request.watchers ]
    end

    # Admins, team managers and holders of the reach's badges: the only
    # people who can pass a Reach, so the rest are never loaded.
    def candidates(reach)
      badge_ids = reach.grants.map { |badge, _team| badge.id }
      Person.where(id: Person.joins(:user).where(users: { admin: true }).select(:id))
        .or(Person.where(id: Membership.where(manager: true).select(:person_id)))
        .or(Person.where(id: BadgeAssignment.where(badge_id: badge_ids).select(:person_id)))
        .includes(:user).to_a
    end
  end
end
