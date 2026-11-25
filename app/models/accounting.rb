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

  # Cents from an amount typed in dollars ("150", "$1,250.50"); nil when
  # blank or not a number.
  def self.parse_cents(text)
    cleaned = text.to_s.delete("$,").strip
    return nil if cleaned.blank? || !cleaned.match?(/\A-?\d+(\.\d{1,2})?\z/)

    (BigDecimal(cleaned) * 100).to_i
  end

  # The gateways that are accounting sources.
  def self.sources
    Gateway.where.not(type: nil).select { |gateway| gateway.is_a?(Accounting::Provider) }
  end
end
