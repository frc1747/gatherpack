# One browser on one device that has agreed to receive phone notifications.
# No audit trail or hooks: the endpoint and keys shouldn't be copied anywhere.
class PushSubscription < ApplicationRecord
  has_neat_id :psub

  # The server posts to whatever endpoint is stored here, so only the browser
  # vendors' push services are accepted.
  PUSH_SERVICE_HOSTS = %r{\A(fcm\.googleapis\.com|[a-z0-9.-]+\.push\.services\.mozilla\.com|[a-z0-9.-]+\.push\.apple\.com|[a-z0-9.-]+\.notify\.windows\.com)\z}
  ENCODED_KEY = /\A[A-Za-z0-9_-]+={0,2}\z/

  belongs_to :user

  encrypts :p256dh, :auth if ActiveRecord::Encryption.config.has_primary_key?

  validates :endpoint, presence: true, uniqueness: true, length: { maximum: 2048 }
  validates :p256dh, presence: true, format: { with: ENCODED_KEY }, length: { maximum: 128 }
  validates :auth, presence: true, format: { with: ENCODED_KEY }, length: { maximum: 64 }
  validate :endpoint_is_a_push_service

  def self.device_label(user_agent)
    agent = user_agent.to_s
    browser = case agent
    when /Edg/ then "Edge"
    when /SamsungBrowser/ then "Samsung Internet"
    when /Firefox|FxiOS/ then "Firefox"
    when /Chrome|CriOS/ then "Chrome"
    when /Safari|iPhone|iPad/ then "Safari"
    else "Browser"
    end
    device = %w[iPhone iPad Android Windows Linux].find { |name| agent.include?(name) } || ("Mac" if agent.include?("Macintosh"))

    [ browser, device ].compact.join(" on ")
  end

  private
    def endpoint_is_a_push_service
      uri = URI.parse(endpoint.to_s)
      return if uri.is_a?(URI::HTTPS) && uri.userinfo.nil? && uri.port == 443 && uri.host.to_s.match?(PUSH_SERVICE_HOSTS)

      errors.add(:endpoint, "isn't a known push service")
    rescue URI::InvalidURIError
      errors.add(:endpoint, "isn't a known push service")
    end
end
