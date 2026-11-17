class Gateway::WebPushGateway < Gateway
  Gateway.register(self, :push_sending)

  # Keep the private key out of the plain configuration column and the audit log
  # where the Gateway model has an encrypted store for secrets.
  store_accessor (method_defined?(:secret_field?) ? :secrets : :configuration), :private_key
  store_accessor :configuration, :contact, :public_key

  ONLY_ONE_MESSAGE = "Phone notifications already has a gateway. Edit that one instead."
  NOTIFICATION_LIFETIME = 2.days

  validates :contact, presence: true
  validate :only_one_gateway, on: :create

  before_destroy :forget_devices

  def fields
    [ :contact ]
  end

  def identifier_icon
    "bell"
  end

  def routes
    return [] unless GatherPack::PushChannel.available?

    [ { name: "Replace keys", path: Rails.application.routes.url_helpers.edit_gateway_push_keys_path(self) } ]
  end

  def ready?
    public_key.present? && private_key.present?
  end

  # Also runs again if its job is retried, so it must not replace existing keys.
  def finish_setup
    generate_keys unless ready?
  end

  # A browser's subscription is tied to the public key it was made with, so none
  # of the existing ones can receive anything after this.
  def replace_keys
    transaction do
      generate_keys
      forget_devices
    end
  end

  def send_message(subscription, title, path)
    WebPush.payload_send(
      message: { title: title, path: path }.to_json,
      endpoint: subscription.endpoint,
      p256dh: subscription.p256dh,
      auth: subscription.auth,
      vapid: { subject: vapid_subject, public_key: public_key, private_key: private_key },
      ttl: NOTIFICATION_LIFETIME.to_i,
      open_timeout: 5,
      read_timeout: 10
    )
  end

  private
    # Subscriptions are tied to one key pair, so there can only be one gateway.
    def only_one_gateway
      errors.add(:base, ONLY_ONE_MESSAGE) if self.class.exists?
    end

    # A browser's subscription only works with the keys it was made with.
    def forget_devices
      PushSubscription.delete_all
    end

    def generate_keys
      keys = WebPush.generate_key
      update!(public_key: keys.public_key, private_key: keys.private_key)
    end

    # Push services require a mailto: or https: contact.
    def vapid_subject
      contact.match?(/\A(mailto|https):/) ? contact : "mailto:#{contact}"
    end
end
