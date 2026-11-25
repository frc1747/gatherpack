module GatherPack
  # The pages that use Turbo's morphing refresh or skip Turbo's cached preview.
  # Pages join by "controller#action", so a feature can add its own from an
  # initializer. A view can also opt in with content_for(:smooth_refresh, true).
  module SmoothPages
    # Module-level storage — loaded once via require_relative, not Zeitwerk-managed
    @refresh_pages = Set.new
    @no_preview_pages = Set.new

    class << self
      def refresh_on(*pages)
        @refresh_pages.merge(pages)
      end

      def no_preview_on(*pages)
        @no_preview_pages.merge(pages)
      end

      def refresh?(page)
        @refresh_pages.include?(page)
      end

      def no_preview?(page)
        @no_preview_pages.include?(page)
      end

      def reset!
        @refresh_pages = Set.new
        @no_preview_pages = Set.new
      end
    end
  end
end
