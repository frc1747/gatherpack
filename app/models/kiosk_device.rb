# A computer an admin has paired to run the time kiosk with no one signed in
# (see KioskDeviceAuthentication). Pairing happens once, through a one-time
# link; the browser then keeps a cookie holding the device's id and secret.
# Only digests of the secret and the pairing code are stored.
class KioskDevice < ApplicationRecord
  has_neat_id :kdv
  has_paper_trail versions: { class_name: "AuditLog" }, ignore: [ :last_seen_at ], skip: [ :secret_digest, :pairing_code_digest ]

  belongs_to :created_by, class_name: "User", optional: true

  # How long a pairing link works.
  PAIRING_LIFETIME = 1.hour
  # last_seen_at is written at most this often.
  SEEN_INTERVAL = 1.hour

  validates :name, presence: true

  scope :active, -> { where(revoked_at: nil) }

  def self.enabled?
    GatherPack::Features.enabled?(:time_tracking) && GatherPack::Features.enabled?(:kiosk_devices)
  end

  def self.digest(value)
    Digest::SHA256.hexdigest(value)
  end

  # The device a pairing link's code belongs to, while it is unused and
  # unexpired.
  def self.find_by_pairing_code(code)
    return if code.blank?

    active.where("pairing_expires_at > ?", Time.current).find_by(pairing_code_digest: digest(code))
  end

  # The device a kiosk_device cookie ("<id>:<secret>") names, unless it is
  # revoked or the secret doesn't match.
  def self.authenticate(value)
    id, secret = value.to_s.split(":", 2)
    return if id.blank? || secret.blank?

    device = active.find_by(id: id)
    device if device&.secret_digest.present? && ActiveSupport::SecurityUtils.secure_compare(device.secret_digest, digest(secret))
  end

  def identifier_name
    name
  end

  def identifier_icon
    "desktop"
  end

  # Issues a new pairing code and returns it. Whatever browser held the old
  # secret stops working, and a revoked device can be paired again.
  def issue_pairing_code!
    code = SecureRandom.urlsafe_base64(32)
    update!(secret_digest: nil, revoked_at: nil, pairing_code_digest: self.class.digest(code), pairing_expires_at: PAIRING_LIFETIME.from_now)
    code
  end

  # Uses up the pairing code and returns the device's new secret, or nil when
  # the code was used or expired in the meantime.
  def pair!(code)
    with_lock do
      return unless pairing_code_digest.present? && pairing_expires_at&.future? && revoked_at.nil? &&
        ActiveSupport::SecurityUtils.secure_compare(pairing_code_digest, self.class.digest(code))

      secret = SecureRandom.urlsafe_base64(32)
      update!(secret_digest: self.class.digest(secret), pairing_code_digest: nil, pairing_expires_at: nil, last_seen_at: Time.current)
      secret
    end
  end

  # Ends the device on its next request.
  def revoke!
    update!(revoked_at: Time.current, secret_digest: nil, pairing_code_digest: nil, pairing_expires_at: nil)
  end

  def revoked?
    revoked_at.present?
  end

  def paired?
    secret_digest.present?
  end

  def pairing?
    pairing_code_digest.present? && pairing_expires_at&.future?
  end

  def seen!
    update_column(:last_seen_at, Time.current) if last_seen_at.nil? || last_seen_at < SEEN_INTERVAL.ago
  end

  # The kiosk is run by kiosk accounts (see TimeKioskPolicy#use?); a paired
  # device stands in for one, with no person behind it.
  def kiosk?
    true
  end
end
