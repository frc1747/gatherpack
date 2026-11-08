# A team on one of a registration's lists: people may apply to it (apply),
# approval also adds them to it (also_add), the approving manager picks one
# of these (pick_one), or a guardian joins it (guardian_also_add).
class Intake::RegistrationTeam < ApplicationRecord
  has_paper_trail versions: { class_name: "AuditLog" }

  belongs_to :registration, class_name: "Intake::Registration", inverse_of: :registration_teams
  belongs_to :team

  enum :kind, { apply: 0, also_add: 1, pick_one: 2, guardian_also_add: 3 }

  validates :team_id, uniqueness: { scope: [ :registration_id, :kind ] }
end
