# One household's sign-up through a registration. From the self-service
# link it holds only a name, an email and the chosen teams until the email is
# confirmed; no person or login exists before then. From the kiosk the
# person is created at once (person_id set) and the link sets a password.
#
# The email and facts are encrypted. The link's token is stored only as a
# digest, works once, and stops working at expires_at.
class Intake::Entry < ApplicationRecord
  has_neat_id :ient
  include CanBeHooked
  has_paper_trail versions: { class_name: "AuditLog" }, ignore: [ :token_digest ]

  belongs_to :registration, class_name: "Intake::Registration", inverse_of: :entries
  belongs_to :person, optional: true
  has_many :household_members, class_name: "Intake::HouseholdMember", dependent: :destroy, inverse_of: :entry

  enum :source, { link: 0, kiosk: 1 }, prefix: true

  serialize :facts, coder: JSON
  encrypts :email
  encrypts :facts

  validates :first_name, :last_name, presence: true, length: { maximum: 100 }
  validates :email, presence: true, length: { maximum: 254 }, format: { with: URI::MailTo::EMAIL_REGEXP }, unless: :verified_at?
  validate :chooses_a_team

  scope :unverified, -> { where(verified_at: nil) }
  scope :verified, -> { where.not(verified_at: nil) }

  # Unverified entries older than this are deleted by Intake::EntryExpiryJob.
  def self.retention_cutoff
    Intake.setting(:intake_entry_days, 7).days.ago
  end

  def self.expired
    unverified.where(created_at: ...retention_cutoff)
  end

  # The entry an unused, unexpired link belongs to, or nil.
  def self.find_by_token(token)
    return if token.blank?
    unverified.where("expires_at > ?", Time.current).find_by(token_digest: Intake.digest(token))
  end

  def facts
    super || {}
  end

  def team_ids
    Array(facts["team_ids"])
  end

  # The registration's teams this entry chose, in a stable order.
  def teams
    registration.apply_teams.where(id: team_ids)
  end

  def team_names
    teams.map(&:name).to_sentence
  end

  # A new link, replacing any earlier one. Returns the token for the email;
  # only its digest is saved.
  def issue_token!
    token = Intake.new_token
    update!(token_digest: Intake.digest(token), expires_at: Intake.setting(:intake_link_hours, 48).hours.from_now)
    token
  end

  def verify!(person)
    update!(token_digest: nil, verified_at: Time.current, person: person)
    Intake.fire("intake_entries - verified", self)
  end

  def household_people
    Person.where(id: household_members.where.not(person_id: nil).select(:person_id))
  end

  def identifier_icon
    "user-plus"
  end

  def identifier_name
    "#{first_name} #{last_name}"
  end

  private

  def chooses_a_team
    errors.add(:base, "Choose at least one team.") if team_ids.empty?
  end
end
