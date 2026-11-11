# Shared setup for the phone notification tests. Flags are set through Settings
# against a throwaway store, so the shared settings file is never written.
module PhoneNotificationsTestSupport
  FLAGS = %i[feature_phone_notifications feature_installable_app].freeze
  ENDPOINT = "https://fcm.googleapis.com/fcm/send/abc123".freeze

  def use_throwaway_settings
    @settings_store = Settings.instance.store
    @settings_file = Tempfile.new([ "settings", ".pstore" ])
    Settings.instance.store = PStore.new(@settings_file.path)
    @flag_values = FLAGS.index_with { |key| Settings.get(key).instance_variable_get(:@value) }
  end

  def restore_settings
    @flag_values.each { |key, value| Settings.get(key).instance_variable_set(:@value, value) }
    Settings.instance.store = @settings_store
    @settings_file.close!
  end

  def set_push_flag(on)
    Settings.set(:feature_phone_notifications, on.to_s)
    Settings.set(:feature_installable_app, "true")
  end

  def create_push_gateway
    Gateway::WebPushGateway.create!(name: "Phones", contact: "admin@example.com").tap(&:finish_setup)
  end

  def create_subscription(user, endpoint: ENDPOINT)
    PushSubscription.create!(user: user, endpoint: endpoint, p256dh: "BPublicKey", auth: "authSecret")
  end

  def enable_topics(user, *topics)
    PushPreference.find_or_create_by!(user: user).update!(enabled_topics: topics.map(&:to_s))
    user.reload
  end

  # Replaces a singleton method for the length of the block.
  def replacing(object, name, replacement)
    original = object.method(name)
    object.define_singleton_method(name, &replacement)
    yield
  ensure
    object.define_singleton_method(name, original)
  end
end
