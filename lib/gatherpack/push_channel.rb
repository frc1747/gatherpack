module GatherPack
  # Sends a phone notification to someone who has opted in. It's an addition to
  # email and never a replacement: each notification is its own job, so a failure
  # here can't affect an email.
  module PushChannel
    class NonLocalPath < ArgumentError; end

    # Push services limit a payload to about 4 KB; a lock screen shows far less.
    TITLE_LIMIT = 120

    class << self
      # Delivery needs the service worker, which removes itself when the
      # installable app is off, so sending then would only lose the subscription.
      def available?
        Features.enabled?(:phone_notifications) && Features.enabled?(:installable_app)
      end

      def gateway
        configured = Gateway[:push_sending]
        configured if configured&.ready?
      end

      # The title and path are all that leave the server. Keep other people's
      # names and personal details out of the title: a lock screen may be in view.
      def deliver(person, topic:, title:, path:)
        raise NonLocalPath, "#{path.inspect} is not a local path" unless local_path?(path)
        return unless available?

        sender = gateway
        user = person.user
        return unless sender && user&.push_topic_enabled?(topic)

        title = title.to_s.squish.truncate(TITLE_LIMIT)
        user.push_subscriptions.find_each do |subscription|
          SendPushJob.perform_later(sender, subscription, title, path)
        end
      end

      # A leading "//" or "/\" is another site as far as a browser is concerned.
      def local_path?(path)
        path.is_a?(String) && path.match?(%r{\A/(?![/\\])[^\s\\]*\z})
      end
    end
  end
end
