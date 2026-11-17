module GatherPack
  # Extra entries for Hook.catalog, so a feature or plugin can offer its own
  # hook events without editing the built-in list.
  #
  #   GatherPack::HookCatalog.register_targets("widgets")       # widgets - create/update/destroy
  #   GatherPack::HookCatalog.register_events("widgets - published")
  #
  # Module-level storage — loaded once via require_relative, not Zeitwerk-managed
  module HookCatalog
    @targets = []
    @events = []

    class << self
      attr_reader :targets, :events

      def register_targets(*names)
        @targets |= names.flatten.map(&:to_s)
      end

      def register_events(*names)
        @events |= names.flatten.map(&:to_s)
      end

      # Each target's create, update and destroy events, then the extra events.
      def entries
        @targets.product([ "create", "update", "destroy" ]).map { |pair| pair.join(" - ") } + @events
      end

      def reset!
        @targets = []
        @events = []
      end
    end
  end
end
