class Gateway < ApplicationRecord
  has_neat_id :gw
  include CanBeHooked
  has_paper_trail versions: { class_name: "AuditLog" }

  class << self
    def registry
      @@registry ||= {}
    end

    def register(klass, svc)
      registry[svc] ||= []
      registry[svc] << klass
    end

    def any_registered?(svc)
      registry[svc.to_sym] ||= []
      registry[svc.to_sym].flat_map(&:all).any?
    end

    def registered(svc)
      registry[svc.to_sym] ||= []
      registry[svc.to_sym].flat_map(&:all)
    end

    def [](svc)
      registry[svc.to_sym] ||= []
      registry[svc.to_sym].flat_map(&:all).first
    end
  end

  after_create :start_finalizing_setup

  def start_finalizing_setup
    FinalizeGatewaySetupJob.perform_later(self)
  end

  def gateway_name
    self.class.to_s.split("::").last
  end

  def finish_setup
  end

  def routes
    []
  end

  def handle_webhook(payload, headers)
  end

  # Checks that a webhook request really comes from the gateway's service,
  # before it is queued for handle_webhook. Gateways that receive webhooks
  # override this; the rest refuse every request.
  def verify_webhook(payload, headers)
    false
  end

  # The HTTP status a refused webhook request is answered with.
  def webhook_refusal_status
    :bad_request
  end

  # Request headers verify_webhook needs. Only webhook_headers are passed on
  # to the job.
  def self.webhook_verification_headers
    webhook_headers
  end

  # Extra options for this gateway's webhook URL, e.g. credentials.
  def webhook_url_options
    {}
  end

  # Parameters the edit form may send besides #fields, e.g. one-off actions.
  def extra_params
    []
  end

  # A short note for the gateway page when this gateway can't accept
  # webhooks yet, or nil when it can.
  def webhook_problem
  end

  def self.webhook_headers
    []
  end
end
