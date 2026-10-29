class CheckinPolicy < ApplicationPolicy
  class Scope < ApplicationPolicy::Scope
    def resolve
      scope.all
    end
  end

  # Records are loaded through Scope, which decides who may see them.
  def show?
    true
  end

  # Admins check in anyone. The event's managers check in themselves and the
  # people they manage, locked event or not. Anyone else checks in only
  # themselves, and only while the event is unlocked.
  def create?
    return new? if record.person.nil?
    return false unless new? && visible?(record.person)

    user.admin? || record.person == person || (manages?(record.event.team) && manages?(record.person))
  end

  # Whether the user may check anyone in on this event at all.
  def new?
    user.admin? || manages?(record.event.team) || !record.event.locked?
  end

  def update?
    record.person == person || user.admin || (record.event.team && record.event.team.manager?(person))
  end

  def destroy?
    update?
  end

  # Anyone who may see the event sees who checked in, but the notes on a
  # check-in are for admins, the event's managers and the person checked in.
  def show_notes?
    user.admin? || record.person == person || manages?(record.event.team)
  end

  private

  def visible?(other)
    PersonPolicy::Scope.new(user, Person).resolve.exists?(id: other.id)
  end
end
