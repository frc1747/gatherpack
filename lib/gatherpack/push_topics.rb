module GatherPack
  # What people can choose to be notified about on their phone. A feature
  # registers its own topic; the settings page lists whatever is registered.
  module PushTopics
    Topic = Struct.new(:key, :label, :hint, :default_on, :available, keyword_init: true) do
      # Whether the topic is offered now; a topic can depend on a feature being on.
      def available?
        available.nil? || available.call
      end
    end

    # Module-level storage — loaded once via require_relative, not Zeitwerk-managed
    @topics = {}

    class << self
      # Registering the same key again replaces it, so reloading code is safe.
      # available: is an optional lambda; the topic is left out while it returns false.
      def register(key, label:, hint: nil, default_on: true, available: nil)
        @topics[key.to_sym] = Topic.new(key: key.to_sym, label: label, hint: hint, default_on: default_on, available: available)
      end

      def all
        @topics.values.select(&:available?)
      end

      def [](key)
        topic = @topics[key.to_sym]
        topic if topic&.available?
      end

      def keys
        all.map(&:key)
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
