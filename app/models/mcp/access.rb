# Who may use the MCP server. The badge limit applies to admins too, so it
# can be used for a trial.
module Mcp::Access
  class << self
    def enabled?
      GatherPack::Features.enabled?(:mcp) && GatherPack::Features.enabled?(:oauth_provider)
    end

    def allowed?(user)
      enabled? && user&.person.present? && badge_allows?(user.person)
    end

    def writes_enabled?
      Settings[:mcp_write_enabled] == true
    end

    private

    # A setting that names no badge (a typo, a deleted badge) lets no one in.
    def badge_allows?(person)
      neat_id = Settings[:mcp_allowed_badge].to_s.strip
      return true if neat_id.blank?

      badge = Mcp.find_by_neat_id(Badge, neat_id)
      badge.present? && person.badge_assignments.exists?(badge: badge)
    end
  end
end
