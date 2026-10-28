class CheckinPolicy < ApplicationPolicy
  class Scope < ApplicationPolicy::Scope
    def resolve
      scope.all
    end
  end

  def create?
    !record.event.locked? || user.admin || (record.event.team && record.event.team.manager?(person))
  end

  def new?
    create?
  end

  def update?
    record.person == person || user.admin || (record.event.team && record.event.team.manager?(person))
  end

  # Anyone who may see the event sees who checked in, but the notes on a
  # check-in are for admins, the event's managers and the person checked in.
  def show_notes?
    user.admin? || record.person == person || manages?(record.event.team)
  end
end
