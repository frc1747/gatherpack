module EmailLog
  # Reads the time an event happened from a webhook payload; now when it's
  # missing or unreadable.
  module WebhookTime
    def self.parse(value)
      Time.zone.parse(value.to_s) || Time.current
    rescue ArgumentError
      Time.current
    end
  end
end
