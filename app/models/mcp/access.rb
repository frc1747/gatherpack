# Who may use the MCP server. The badge limit applies to admins too, so it
# can be used for a trial.
module Mcp::Access
  class << self
    def enabled?
      stored_setting(:feature_mcp) == "true" && GatherPack::Features.enabled?(:oauth_provider)
    end

    def allowed?(user)
      enabled? && user&.person.present? && badge_allows?(user.person)
    end

    def writes_enabled?
      stored_setting(:mcp_write_enabled) == "true"
    end

    # The setting as saved in the store, not the per-process copy, which a
    # save through another web worker leaves stale. Used for the settings that
    # decide who can connect, and by the settings page so it can't show (and
    # re-save) an old value.
    def stored_setting(key)
      setting = Settings.get(key)
      store = Settings.instance.store
      store.transaction(true) { store.fetch(key, setting.default_value) }.to_s
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
