module GatherPack
  # What people can choose to be notified about on their phone. A feature
  # registers its own topic; the settings page lists whatever is registered.
  module PushTopics
    Topic = Struct.new(:key, :label, :hint, :default_on, keyword_init: true)

    # Module-level storage — loaded once via require_relative, not Zeitwerk-managed
    @topics = {}

    class << self
      # Registering the same key again replaces it, so reloading code is safe.
      def register(key, label:, hint: nil, default_on: true)
        @topics[key.to_sym] = Topic.new(key: key.to_sym, label: label, hint: hint, default_on: default_on)
      end

      def all
        @topics.values
      end

      def [](key)
        @topics[key.to_sym]
      end

      def keys
        @topics.keys
      end

      # What someone gets until they choose for themselves.
      def default_keys
        all.select(&:default_on).map(&:key)
      end

      def reset!
        @topics = {}
      end
    end
  end
end
