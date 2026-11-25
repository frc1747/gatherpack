# Order notices: the timeline entry that sends them, and the status change
# that does (see Orders::EventNotices).
Rails.application.config.to_prepare do
  OrderRequestEvent.include(Orders::EventNotices)
  # A person's notice choice goes with them when they're deleted.
  Person.has_one :order_notice_preference, dependent: :delete
end

# Subscribed once, outside to_prepare, so a development reload doesn't add
# another subscriber. The block finds the class when it runs.
ActiveSupport::Notifications.subscribe("order_request_changed.gatherpack") do |*, payload|
  Orders::EventNotices.request_changed(payload)
end
