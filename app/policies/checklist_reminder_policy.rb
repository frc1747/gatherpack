# Who may remind a checklist's people and set up its reminders: whoever runs
# it (an admin, a manager of its team or a team above, or one of its
# organizers). Reminders go only from an active checklist (people can't open
# a draft); its Reminders section can be set up while it isn't archived. The
# record is the Checklist.
class ChecklistReminderPolicy < ApplicationPolicy
  def create?
    update? && record.active?
  end

  def update?
    ChecklistReminder.enabled? && !record.archived? && record.organizer?(person)
  end

  alias_method :new?, :create?
  alias_method :show?, :update?
  alias_method :index?, :update?
end
