class Gateway::PostmarkReceivingGateway < Gateway
  Gateway.register(self, :email_receiving)
  store_accessor :configuration, :server_token
  store_accessor :configuration, :inbound_password

  # Postmark signs in to the inbound webhook with HTTP basic auth, using the
  # credentials in the inbound URL (https://user:password@host/...).
  INBOUND_USER = "postmark".freeze

  attr_accessor :regenerate_inbound_password

  before_save :generate_inbound_password, if: -> { (new_record? && inbound_password.blank?) || ActiveModel::Type::Boolean.new.cast(regenerate_inbound_password) }

  def fields
    [ :server_token ]
  end

  def extra_params
    [ :regenerate_inbound_password ]
  end

  def identifier_icon
    "envelope-open-text"
  end

  def self.webhook_verification_headers
    [ "HTTP_AUTHORIZATION" ]
  end

  def verify_webhook(body, headers)
    if inbound_password.blank?
      Rails.logger.error("Gateway::PostmarkReceivingGateway##{id} (#{name}) refused inbound mail: this gateway has no inbound password. Regenerate it on the gateway page and update the inbound webhook URL in Postmark.")
      return false
    end

    user, password = basic_credentials(headers["HTTP_AUTHORIZATION"])
    return false if user.nil? || password.nil?

    user_matches = ActiveSupport::SecurityUtils.secure_compare(user, INBOUND_USER)
    password_matches = ActiveSupport::SecurityUtils.secure_compare(password, inbound_password)
    user_matches && password_matches
  end

  def webhook_refusal_status
    :unauthorized
  end

  def webhook_url_options
    { user: INBOUND_USER, password: inbound_password }
  end

  def webhook_problem
    "not ready: no inbound password" if inbound_password.blank?
  end

  def handle_webhook(body, headers)
    payload = JSON.parse(body)
    (payload["ToFull"] + payload["CcFull"] + payload["BccFull"]).each do |recipient|
      if mb = Mailbox.where(address: recipient["Email"]).first
        MailboxMessage.create(mailbox: mb, from: payload["FromFull"]["Email"], subject: payload["Subject"], body: payload["HtmlBody"] || payload["TextBody"])
      end
    end
  end

  def finish_setup
    client = Postmark::ApiClient.new(server_token)
  end

  private
    def generate_inbound_password
      self.inbound_password = SecureRandom.alphanumeric(32)
      self.regenerate_inbound_password = nil
    end

    def basic_credentials(header)
      scheme, encoded = header.to_s.split(" ", 2)
      return unless scheme&.casecmp?("Basic") && encoded.present?

      Base64.decode64(encoded).split(":", 2)
    end
end
