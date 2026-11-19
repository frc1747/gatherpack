module GatherPack
  # Other cards on a person's Notifications page, below the phone settings: a
  # feature registers a partial (for example, how its emails reach the person)
  # and the page shows it while its visible proc says so. The page is reachable
  # while phone notifications are set up or any section is visible.
  module NotificationSections
    Section = Struct.new(:key, :partial, :position, :visible, keyword_init: true)

    # Module-level storage — loaded once via require_relative, not Zeitwerk-managed
    @sections = {}

    class << self
      # Registering the same key again replaces it, so reloading code is safe.
      # visible is called with the signed-in user.
      def register(key, partial:, position: 100, visible: ->(_user) { true })
        @sections[key.to_sym] = Section.new(key: key.to_sym, partial: partial, position: position, visible: visible)
      end

      def unregister(key)
        @sections.delete(key.to_sym)
      end

      # The sections to show this user, in position order.
      def visible_for(user)
        return [] if user.nil?

        @sections.values.select { |section| section.visible.call(user) }.sort_by(&:position)
      end

      def any_for?(user)
        visible_for(user).any?
      end

      # Whether the user's Notifications page has anything on it.
      def page_for?(user)
        GatherPack::PushChannel.available? || any_for?(user)
      end

      def registered
        @sections
      end

      def reset!
        @sections = {}
      end
    end
  end
end
