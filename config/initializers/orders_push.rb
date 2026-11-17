# Phone notifications for orders, on top of the emails OrderNotices sends. The
# topic is offered only while orders is on; nothing is pushed while it or phone
# notifications are off.
Rails.application.config.to_prepare do
  OrderNotices.prepend(OrdersPushConnector)

  GatherPack::PushTopics.register(:orders, label: "Orders", hint: "When a request needs you or something changes on one", default_on: false,
    available: -> { GatherPack::Features.enabled?(:orders) })
end
