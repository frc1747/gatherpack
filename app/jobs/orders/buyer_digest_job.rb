# Daily: tells each buyer about the approved requests waiting to be bought.
class Orders::BuyerDigestJob < ApplicationJob
  queue_as :default

  def perform
    Orders::Reminders.buyer_digest
  end
end
