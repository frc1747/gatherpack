# The orders reports (spec §3.12) are for people who run orders: admins,
# team managers, approvers, buyers and funding managers. Orders::Reports
# limits what each sees to the teams they reach.
class OrderReportPolicy < ApplicationPolicy
  def index?
    return false if person.nil?

    access = Orders::Access.for(person)
    access.admin? || access.managed_team_ids.any? || access.approver? || access.buyer? || access.funding_manager?
  end

  def show?
    index?
  end
end
