# The people a requester can add as followers of a request: members of the
# request's team and the teams above it (where mentors usually sit), other
# than the requester and those already following. Only their names show.
module Orders
  module WatcherCandidates
    module_function

    def for(order_request)
      team_ids = [ order_request.team_id ] + order_request.team.all_ancestor_ids
      taken = [ order_request.requested_by_id ] + order_request.order_request_watchers.map(&:person_id)
      Person.where(id: Membership.where(team_id: team_ids).select(:person_id))
        .where.not(id: taken)
        .order(:display_name)
    end
  end
end
