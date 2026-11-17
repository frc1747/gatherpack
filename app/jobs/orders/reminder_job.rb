# Daily: the once-only reminders for requests needed soon and requests
# nobody has decided.
class Orders::ReminderJob < ApplicationJob
  queue_as :default

  def perform
    Orders::Reminders.needed_soon
    Orders::Reminders.undecided
  end
end
