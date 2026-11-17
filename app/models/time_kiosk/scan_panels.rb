# The seam the time kiosk offers other features, so they can add to the card
# shown after a scan without editing its views. Register from a
# config.to_prepare block so the registrations come back after a development
# reload:
#
#   Rails.application.config.to_prepare do
#     # Rendered at the bottom of the card, with the local person: (the
#     # person whose card was scanned) and nothing else. The partial may
#     # render nothing.
#     TimeKiosk::ScanPanels.register(:my_feature, partial: "my_feature/kiosk_panel")
#   end
#
# Registering the same key again replaces the earlier entry.
module TimeKiosk::ScanPanels
  Panel = Struct.new(:key, :partial, keyword_init: true)

  class << self
    def register(key, partial:)
      registry[key.to_sym] = Panel.new(key: key.to_sym, partial: partial)
    end

    def all
      registry.values
    end

    def reset!
      registry.clear
    end

    private

    def registry
      @registry ||= {}
    end
  end
end
