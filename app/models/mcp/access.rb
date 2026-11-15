# Who may use the MCP server. The badge limit applies to admins too, so it
# can be used for a trial. A kiosk account is kept to the time kiosk (see
# KioskConfinement), so it is refused here too, even with a token made by hand.
module Mcp::Access
  class << self
    def enabled?
      stored_setting(:feature_mcp) == "true" && stored_setting(:feature_oauth_provider) == "true"
    end

    def allowed?(user)
      enabled? && user&.person.present? && !user.kiosk_account? && badge_allows?(user.person)
    end

    def writes_enabled?
      stored_setting(:mcp_write_enabled) == "true"
    end

    def dynamic_pages_enabled?
      stored_setting(:mcp_dynamic_pages_enabled) == "true"
    end

    # The setting as saved in the store, not the per-process copy, which a
    # save through another web worker leaves stale. Used for the settings that
    # decide who can connect.
    def stored_setting(key)
      default = Settings.get(key)&.default_value
      store = Settings.instance.store
      store.transaction(true) { store.fetch(key, default) }.to_s
    end

    # Settings this module decides on, refreshed on the settings page.
    SETTING_KEYS = %i[feature_mcp feature_oauth_provider mcp_write_enabled mcp_dynamic_pages_enabled mcp_allowed_badge].freeze

    # Sets this process's cached copies from the store, without writing, so a
    # page rendered here shows (and a full-form save keeps) what was saved
    # through another web worker.
    def refresh_settings
      SETTING_KEYS.each do |key|
        Settings.get(key)&.instance_variable_set(:@value, stored_setting(key))
      end
    end

    private

    # A setting that names no badge (a typo, a deleted badge) lets no one in.
    def badge_allows?(person)
      neat_id = stored_setting(:mcp_allowed_badge).strip
      return true if neat_id.blank?

      badge = Mcp.find_by_neat_id(Badge, neat_id)
      badge.present? && person.badge_assignments.exists?(badge: badge)
    end
  end
end
