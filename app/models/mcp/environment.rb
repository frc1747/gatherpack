# Tells AI clients whether this server is the live system. GP_ENVIRONMENT sets it,
# because staging and demo copies also run with RAILS_ENV=production and a copy of
# the live settings. Only an explicit "non-production" says a production build isn't
# live, so a missing or mistyped value can't make live data look safe to change.
module Mcp::Environment
  PRODUCTION = "production".freeze
  NON_PRODUCTION = "non-production".freeze
  META_KEY = "gatherpack/environment".freeze

  NOTICES = {
    PRODUCTION => "Environment: production. This is the live system: its records are real, and changes take effect immediately.",
    NON_PRODUCTION => "Environment: non-production. This isn't the live system, so changes here don't reach production. " \
      "Its data may be a copy of live data: treat it with the same care."
  }.freeze

  class << self
    def current
      case ENV["GP_ENVIRONMENT"].to_s.strip.downcase
      when NON_PRODUCTION then NON_PRODUCTION
      when "" then Rails.env.production? ? PRODUCTION : NON_PRODUCTION
      else PRODUCTION
      end
    end

    def notice
      NOTICES.fetch(current)
    end

    # What every tool result carries: a text block, which clients show the model,
    # and _meta, which is for the client's own code and usually isn't shown.
    def notice_block
      { type: "text", text: notice }
    end

    def meta
      { META_KEY => current }
    end
  end
end
