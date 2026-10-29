class User < ApplicationRecord
  has_neat_id :usr
  include CanBeHooked
  has_paper_trail versions: { class_name: "AuditLog" }, ignore: [ :encrypted_password, :failed_attempts, :locked_at ], skip: :session_token
  has_one :person
  has_many :access_grants, class_name: "Doorkeeper::AccessGrant", foreign_key: :resource_owner_id, dependent: :delete_all
  has_many :access_tokens, class_name: "Doorkeeper::AccessToken", foreign_key: :resource_owner_id, dependent: :delete_all
  accepts_nested_attributes_for :person
  # Include default devise modules. Others available are:
  # :confirmable, :lockable, :timeoutable, :trackable and :omniauthable
  devise :database_authenticatable, :registerable, :recoverable, :rememberable, :validatable, :lockable, :timeoutable, :omniauthable, omniauth_providers: [ :developer, :google_oauth2, :discord, :github ]

  validate :password_change, on: :update
  before_save :fill_missing_defaults
  after_update :revoke_api_access, if: :saved_change_to_encrypted_password?
  # An app authorized before the account became a kiosk account (flagged
  # kiosk and not an admin, either by gaining the flag or losing admin)
  # shouldn't act for it. (A second `after_update :revoke_api_access` would
  # replace the one above.)
  after_update -> { revoke_api_access }, if: -> { kiosk? && !admin? && (saved_change_to_kiosk? || saved_change_to_admin?) }

  after_create :adminify_first_user

  attr_accessor :old_password, :acting_user

  # A login email is only searchable by admins.
  def self.ransackable_attributes(auth_object = nil)
    if auth_object.respond_to?(:admin?) && auth_object.admin?
      [ "email" ]
    else
      []
    end
  end

  # User search matches the person's name as well as the email.
  def self.ransackable_associations(auth_object = nil)
    [ "person" ]
  end

  # Users have no name of their own; show their person's, or their email.
  def identifier_name
    person&.display_name.presence || email
  end

  def identifier_icon
    "user"
  end

  # A lock only refuses passwords (Lockable#valid_for_authentication? still
  # does): it doesn't end sessions already signed in or refuse provider
  # sign-in, so whoever locks an account by guessing can't sign its owner out.
  def active_for_authentication?
    super || access_locked?
  end

  # Devise checks session and remember-me cookies against this. The password
  # hash's salt ends them when the password changes; the session token ends
  # them when the user signs out (see rotate_session_token!).
  def authenticatable_salt
    "#{super}#{session_token}"
  end

  # Ends every session of this login, on every device.
  def rotate_session_token!
    update_columns(session_token: SecureRandom.uuid)
  end

  def self.create_from_provider_data(provider_data)
    if Settings[:oauth_signup]
      where(provider: provider_data.provider, uid: provider_data.uid).first_or_create  do |user|
        user.email = provider_data.info.email
        user.password = Devise.friendly_token[0, 20]
        user.person = Person.new
        user.person.first_name = provider_data.info.first_name
        user.person.last_name = provider_data.info.last_name
      end
    else
      find_by(email: provider_data.info.email).update(provider: provider_data.provider, uid: provider_data.uid)
    end
  end

  private

  # Reverting an audit entry restores the columns it doesn't hold as nil: the
  # session token is never recorded, and entries written before the lockout
  # columns existed lack those. A reverted login gets a new session token,
  # which signs it out everywhere.
  def fill_missing_defaults
    self.session_token = SecureRandom.uuid if session_token.blank?
    self.failed_attempts ||= 0
  end

  def adminify_first_user
    if User.count == 1
      User.first.update(admin: true)
    end
  end

  # Changing your own password or email takes your current password, admins
  # included, so a session left open or copied can't be used to take the
  # account over. Who may change someone else's login is up to UserPolicy.
  def password_change
    return unless persisted? && acting_user == self
    return unless password.present? || will_save_change_to_email?

    unless old_password.present? && Devise::Encryptor.compare(User, encrypted_password_was, old_password)
      errors.add(:old_password, "must be your current password to change your email or password.")
    end
  end

  # A new password also ends the access apps were given with the old one,
  # and so does becoming a kiosk account.
  def revoke_api_access
    access_tokens.where(revoked_at: nil).update_all(revoked_at: Time.current)
    access_grants.where(revoked_at: nil).update_all(revoked_at: Time.current)
  end

  def password_required?
    self.new_record? || self.password.present?
  end
end
