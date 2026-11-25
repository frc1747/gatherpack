# Who hears about a request (spec §3.11). Approvers and buyers are found
# from the settings' grants the same way the pages decide who may act, so a
# notice reaches exactly the people who have the item on their list. With
# the notices_admins_everywhere setting off, admins hear only through their
# own roles, or when nobody else would get the notice.
module Orders
  module Recipients
    module_function

    # Everyone who may decide the step on the request: not its requester or
    # their relatives, who can't decide it.
    def approvers(order_request, step)
      return [] if step.nil?

      to_notify(candidates(step.reach)) do |access|
        access.approver_on?(step, order_request.team_id) && !access.own_or_relative?(order_request)
      end
    end

    # Buyers whose reach includes the team.
    def buyers(team_id)
      to_notify(candidates(Orders::Config.buyers)) { |access| access.buyer_for?(team_id) }
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

    # The candidates the block passes, judged by the roles that bring
    # notices. When none of them would get an email (nobody holds the role,
    # or those who do have no address or turned order emails off), the
    # admins the block passes by permission are added.
    def to_notify(candidates)
      people = candidates.select { |person| yield Orders::Access.new(person, for_notices: true) }
      return people if people.any? { |person| person.user&.email.present? && Orders::Config.delivery_for(person) != :off }

      people | candidates.select { |person| person.admin? && yield(Orders::Access.new(person)) }
    end
  end
end
