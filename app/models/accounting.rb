# Accounting: account status, reminders and billing from a group's books.
# Sources (Accounting::Provider gateways) copy records into
# AccountingRecord; everything else reads those records' neutral columns.
module Accounting
  # Raised by a source when it can't sign in any more and a person has to
  # connect it again.
  class ReconnectNeeded < StandardError; end

  # Raised for a refusal worth trying again later (rate limits, outages).
  class TemporaryFailure < StandardError; end

  def self.enabled?
    GatherPack::Features.enabled?(:accounting)
  end

  # The gateways that are accounting sources.
  def self.sources
    Gateway.where.not(type: nil).select { |gateway| gateway.is_a?(Accounting::Provider) }
  end
end
