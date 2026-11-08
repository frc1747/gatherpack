require_relative "../../lib/gatherpack/push_topics"
require_relative "../../lib/gatherpack/push_channel"

# Phone notifications: people opt in per device and per topic, on top of email.
# Connector branches register their own topics and prepend onto their own senders.
Rails.application.config.filter_parameters += [ /\A(endpoint|p256dh|auth)\z/ ]

Rails.application.config.to_prepare do
  GatherPack::Features.register(
    GatherPack::Feature.new(
      key: :phone_notifications,
      label: "Phone notifications",
      description: "Let people get notifications on their phone, on top of email. Needs the installable app.",
      default_enabled: false
    )
  )

  # Loads the gateway so it's in the registry (test and lazy-loading environments).
  Gateway::WebPushGateway

  User.include(PushNotifiable)
  AnnouncementNotificationRouter.prepend(AnnouncementPushConnector)

  GatherPack::PushTopics.register(:announcements, label: "Announcements", hint: "When a leader sends one out", default_on: false)

  GatherPack::SidebarSlots.register(:phone_notifications, partial: "notification_settings/sidebar_entry", position: 800,
    visible: ->(_view) { GatherPack::PushChannel.available? && current_user == true_user })
end

# Deletes this device's subscription however sign-out happens, so the next person
# on this browser doesn't get the last person's notifications.
Warden::Manager.before_logout do |user, warden, options|
  next unless user.is_a?(User) && options[:scope] == :user

  subscription_id = warden.raw_session.delete(:push_subscription_id)
  PushSubscription.where(id: subscription_id, user: user).delete_all if subscription_id
end
