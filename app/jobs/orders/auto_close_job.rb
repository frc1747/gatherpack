# Daily: closes received requests after orders_close_after_days.
class Orders::AutoCloseJob < ApplicationJob
  queue_as :default

  def perform
    Orders::Reminders.auto_close
  end
end
