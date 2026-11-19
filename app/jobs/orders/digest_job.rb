# Daily: Orders' own summary email (Orders::Reminders.digest), for the
# people whose choice is a summary while Summaries doesn't send it.
class Orders::DigestJob < ApplicationJob
  queue_as :default

  def perform
    Orders::Reminders.digest
  end
end
