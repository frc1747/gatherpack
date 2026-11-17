require_relative "settings_test_helper"
require_relative "../phone_notifications_test_support"

# Shared setup for the phone notification connector tests. Settings go through
# a throwaway store (SettingsTestHelper), so the feature flags really take effect.
module PushConnectorTestSupport
  include PhoneNotificationsTestSupport

  # Turns on phone notifications and the given features until teardown; push: false turns them off.
  # isolated: false is for tests whose world already swapped in a throwaway
  # store: it writes there and only puts the cached values back.
  def apply_push_settings(push: true, isolated: true, **features)
    values = { feature_phone_notifications: push.to_s, feature_installable_app: "true" }
    features.each { |feature, on| values[:"feature_#{feature}"] = on.to_s }
    return (@push_settings_restores ||= []) << SettingsTestHelper.apply(values) if isolated

    previous = values.keys.to_h { |key| [ key, Settings.get(key).instance_variable_get(:@value) ] }
    values.each { |key, value| Settings[key] = value }
    (@push_settings_restores ||= []) << -> { previous.each { |key, value| Settings.get(key).instance_variable_set(:@value, value) } }
  end

  def restore_push_settings
    @push_settings_restores&.reverse_each(&:call)
  end

  # A user who gets pushes for the topics, on one device.
  def subscribe(person, *topics)
    create_subscription(person.user, endpoint: "https://fcm.googleapis.com/fcm/send/#{person.user.id}")
    enable_topics(person.user, *topics)
  end

  def enqueued_pushes
    enqueued_jobs.select { |job| job[:job] == SendPushJob }
  end

  # The users the enqueued pushes go to, in any order.
  def pushed_user_ids
    ids = PushSubscription.where(id: enqueued_pushes.filter_map { |job| job[:args][1]["_aj_globalid"]&.split("/")&.last }).pluck(:user_id)
    ids.sort
  end

  def push_titles
    enqueued_pushes.map { |job| job[:args][2] }
  end

  def push_paths
    enqueued_pushes.map { |job| job[:args][3] }
  end
end
