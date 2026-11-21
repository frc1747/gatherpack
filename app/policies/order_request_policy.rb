# Who sees and does what on a request (spec §3.8). Drafts are their
# requester's alone. Deciding also follows the approval engine
# (OrderRequest#can_decide?): no approving your own or a relative's request.
class OrderRequestPolicy < ApplicationPolicy
  class Scope < ApplicationPolicy::Scope
    def resolve
      return scope.none if person.nil?

      access = Orders::Access.for(person)
      return scope.where.not(status: :draft).or(scope.where(requested_by_id: person.id)) if access.admin? || access.sees_every_request?

      team_ids = access.managed_team_ids | access.any_approver_team_ids | access.buyer_team_ids
      team_ids |= access.member_team_ids if Orders::Config.team_can_see?
      scope.where(requested_by_id: person.id)
        .or(scope.where.not(status: :draft).where(id: OrderRequestWatcher.where(person_id: person.id).select(:order_request_id)))
        .or(scope.where.not(status: :draft).where(team_id: team_ids.to_a))
    end
  end

  def index?
    person.present?
  end

  def show?
    return false if person.nil?
    return requester? if record.draft?

    involved? || access.sees_every_request?
  end

  # Anyone in orders_requesters may start a request.
  def create?
    person.present? && access.requester?
  end

  # The requester while it's still editable; team managers and admins
  # until it's finished.
  def update?
    return false if person.nil?
    return requester? && record.draft? if record.draft?

    (requester? && record.editable?) || (manager? && !record.finished?)
  end

  # Only a draft can be deleted; anything else is cancelled.
  def destroy?
    record.draft? && (requester? || access.admin?)
  end

  def submit?
    requester? && record.draft?
  end

  def resubmit?
    (requester? || manager?) && record.changes_requested?
  end

  # Before anything is ordered (the model checks that part).
  def cancel?
    requester? || manager?
  end

  def close?
    record.received? && (requester? || manager? || access.buyer_for?(record.team_id))
  end

  # Not on a draft: nobody else sees it yet. Those who see every request
  # (orders_viewers) comment as team members do, when team members can.
  def comment?
    return false if person.nil? || record.draft?

    involved? || (access.sees_every_request? && Orders::Config.team_can_see?)
  end

  # Following would let someone who only sees every request receive, so
  # they can't.
  def follow?
    show? && involved? && !requester?
  end

  # Adding other people as followers.
  def add_watchers?
    requester? || manager?
  end

  def decide?
    record.can_decide?(person)
  end

  # Approvers edit lines on the step they can decide, before approving.
  def approver_edit?
    record.submitted? && decide?
  end

  # Setting the request's funding source: approvers who can decide, and
  # requesters when orders_requesters_pick_funding is on.
  def set_funding?
    access.sets_funding?(record)
  end

  def buy?
    access.buyer_for?(record.team_id)
  end

  # Record deliveries: the requester, followers, members of its team (when
  # they can see it), buyers and managers.
  def receive?
    return false if person.nil? || record.draft?

    requester? || watcher? || team_member? || manager? || access.buyer_for?(record.team_id)
  end

  # Anyone who may start a request for this one's team, who can see it.
  def duplicate?
    show? && access.requester? && access.may_request_for?(record.team_id)
  end

  def order_again?
    requester? && access.requester?
  end

  def see_funding?
    access.staff_for?(record.team_id) || Orders::Config.requesters_pick_funding?
  end

  def see_estimated_shipping?
    access.sees_estimated_shipping?(record)
  end

  private

  def access
    @access ||= Orders::Access.for(person)
  end

  def requester?
    person.present? && record.requested_by_id == person.id
  end

  # Sees the request for a reason of its own, not only through
  # orders_viewers.
  def involved?
    requester? || watcher? || team_member? || manager? || access.any_approver_team_ids.include?(record.team_id) ||
      access.buyer_for?(record.team_id)
  end

  def watcher?
    record.watched_by?(person)
  end

  def team_member?
    Orders::Config.team_can_see? && access.member_team_ids.include?(record.team_id)
  end

  def manager?
    access.manages?(record.team_id)
  end
end
