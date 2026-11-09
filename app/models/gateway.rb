class Gateway < ApplicationRecord
  has_neat_id :gw
  include CanBeHooked
  # API keys, tokens and passwords live in the encrypted secrets column
  # (subclasses declare theirs with store_accessor :secrets), never in the
  # plain configuration column or in the audit log.
  store :secrets, coder: JSON
  encrypts :secrets
  has_paper_trail versions: { class_name: "AuditLog" }, skip: [ :secrets ]

  # Audit log rows don't carry secrets, so a gateway reverted to one of them
  # keeps its current secrets instead of losing them.
  before_save -> { restore_attributes([ :secrets ]) }, if: -> { version.present? && secrets_changed? }
  # Older audit log rows still have secrets in configuration; reverting to
  # one must not write them back in plain text.
  before_save :remove_secrets_from_configuration

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

  def secret_field?(field)
    self.class.stored_attributes.fetch(:secrets, []).include?(field.to_sym)
  end

  # Secrets encrypted with keys this install no longer has (SECRET_KEY_BASE
  # or the encryption keys changed) can't be read. Such a gateway is loaded
  # with empty secrets that don't count as a change, so it can still be
  # shown, edited, deleted and reverted, and the stored ciphertext is only
  # replaced when secrets are entered again (or cleared on purpose).
  after_find -> { secrets }

  def secrets
    super
  rescue ActiveRecord::Encryption::Errors::Decryption
    Rails.logger.error("#{self.class}##{id} (#{name}) has secrets that can't be decrypted (were SECRET_KEY_BASE or the encryption keys changed?). Enter them again on the gateway page.")
    @secrets_unreadable = true
    # An encrypted empty hash, as if loaded from the database. (Serializing
    # {} through the attribute type gives nil, which would count as a change.)
    @attributes.write_from_database("secrets", ActiveRecord::Encryption.encryptor.encrypt({}.to_json))
    super
  end

  def secrets_unreadable?
    secrets
    @secrets_unreadable == true
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

  private
    def remove_secrets_from_configuration
      return unless configuration.is_a?(Hash)

      self.configuration = configuration.except(*self.class.stored_attributes.fetch(:secrets, []).map(&:to_s))
    end
end
