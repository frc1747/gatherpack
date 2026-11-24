# The sent email log (feature_email_log): settings, status labels and the
# patches config/initializers/email_log.rb applies to SendEmailJob and the
# sending gateways. Off, nothing is logged and webhooks behave as before.
module EmailLog
  SETTINGS_GROUP = "Email Log".freeze

  DEFAULT_STATUS_LABELS = {
    "sending" => "Sending",
    "sent" => "Sent",
    "delivered" => "Delivered",
    "bounced" => "Bounced",
    "complained" => "Marked as spam",
    "failed" => "Failed"
  }.freeze

  STATUS_LABEL_SETTINGS = SentEmail::STATUSES.index_with { |status| :"email_log_status_#{status}_label" }.freeze

  DEFAULT_SCANNER_SECONDS = 10

  class << self
    def enabled?
      GatherPack::Features.enabled?(:email_log)
    end

    def status_label(status)
      status = status.to_s
      Settings[STATUS_LABEL_SETTINGS[status]].presence || DEFAULT_STATUS_LABELS.fetch(status, status.humanize)
    end

    # [[label, status], ...] for a choice.
    def status_options
      SentEmail::STATUSES.map { |status| [ status_label(status), status ] }
    end

    def scanner_seconds
      value = Settings[:email_log_scanner_seconds].to_s
      value.match?(/\A\d+\z/) ? value.to_i : DEFAULT_SCANNER_SECONDS
    end

    def register_settings
      register_setting(:email_log_scanner_seconds, :integer, "Ignore Clicks Within (Seconds)", DEFAULT_SCANNER_SECONDS.to_s, SETTINGS_GROUP,
        "Mail scanners follow links as a message arrives. A link click this many seconds or less after delivery is counted but not shown as the person's")
      SentEmail::STATUSES.each do |status|
        register_setting(STATUS_LABEL_SETTINGS[status], :string, "Status Label: #{DEFAULT_STATUS_LABELS[status]}",
          DEFAULT_STATUS_LABELS[status], SETTINGS_GROUP, "The word shown for this status on the Sent email screen")
      end
    end

    private
      # Settings.register where the app has it; otherwise the same call the
      # built-in settings make.
      def register_setting(key, *args)
        if Settings.respond_to?(:register)
          Settings.register(key, *args)
        else
          Settings.instance.send(:add_setting, key, *args)
        end
      end
  end
end
