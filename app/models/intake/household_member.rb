# A person on an entry: the one who signed up (applicant), someone they added
# (ward), or a guardian named by a young person (guardian). A guardian row
# holds the guardian's name and email (encrypted) and a confirmation link
# until the guardian confirms; then person_id is the guardian.
class Intake::HouseholdMember < ApplicationRecord
  has_neat_id :ihm
  has_paper_trail versions: { class_name: "AuditLog" }, ignore: [ :token_digest ]

  belongs_to :entry, class_name: "Intake::Entry", inverse_of: :household_members
  belongs_to :person, optional: true

  enum :role, { applicant: 0, ward: 1, guardian: 2 }

  serialize :facts, coder: JSON
  encrypts :facts

  scope :unconfirmed_guardians, -> { guardian.where(guardian_confirmed_at: nil) }

  def facts
    super || {}
  end

  # The person this guardian row is for (the young person who named them).
  def ward
    Person.find_by(id: facts["ward_id"])
  end

  # Staff-only: someone already on file this person might be.
  def possible_match
    Person.find_by(id: facts["possible_match_id"]) if facts["possible_match_id"]
  end

  def self.find_guardian_by_token(token)
    return if token.blank?
    unconfirmed_guardians.where("token_expires_at > ?", Time.current).find_by(token_digest: Intake.digest(token))
  end

  def issue_token!
    token = Intake.new_token
    update!(token_digest: Intake.digest(token), token_expires_at: Intake.setting(:intake_link_hours, 48).hours.from_now)
    token
  end
end
