# Who may remind a checklist's people and set up its reminders: whoever runs
# it (an admin, a manager of its team or a team above, or one of its
# organizers), while it isn't archived. The record is the Checklist.
class ChecklistReminderPolicy < ApplicationPolicy
  def create?
    ChecklistReminder.enabled? && !record.archived? && record.organizer?(person)
  end

  alias_method :new?, :create?
  alias_method :update?, :create?
  alias_method :show?, :create?
  alias_method :index?, :create?
end
