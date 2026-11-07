# Shared by intake's public pages: their own layout (no navigation, not
# indexed), the feature flag, rate limits, and the audit actor for changes
# made by someone who isn't signed in.
module Intake::PublicPages
  extend ActiveSupport::Concern

  TRY_AGAIN = "Try again in a few minutes.".freeze

  included do
    layout "intake_public"
    before_action :require_intake_feature
  end

  private

  # A switched-off feature looks like an unknown link.
  def require_intake_feature
    render "intake/join/closed", status: :not_found unless Intake.enabled?
  end

  # Counts one request against a limit, as Rails' rate_limit does (a cache
  # counter per key and window), with the limit read from a setting.
  # Returns whether the request is over it.
  def intake_over_limit?(name, by, to:, within:)
    store = Intake.rate_limit_store || Rails.cache
    count = store.increment([ "intake-rate-limit", name, by ].join(":"), 1, expires_in: within)
    over = count.present? && count > to
    ActiveSupport::Notifications.instrument("rate_limit.action_controller", request: request, count: count, to: to, within: within, by: by, name: name) if over
    over
  end

  def verification_over_limit?
    intake_over_limit?("verify", request.remote_ip, to: Intake.setting(:intake_rate_verify_per_hour, 10), within: 1.hour)
  end

  # Changes made for someone who isn't signed in are attributed to their
  # entry. The audit log's whodunnit column is a uuid, so it holds the
  # entry's id itself rather than "entry:<id>"; an id that isn't a user's
  # is an Intake::Entry's.
  def as_entry(entry, &block)
    PaperTrail.request(whodunnit: entry.id, &block)
  end
end
