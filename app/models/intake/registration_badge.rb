# A badge approval also gives (a fact, such as how someone joined).
class Intake::RegistrationBadge < ApplicationRecord
  has_paper_trail versions: { class_name: "AuditLog" }

  belongs_to :registration, class_name: "Intake::Registration", inverse_of: :registration_badges
  belongs_to :badge

  validates :badge_id, uniqueness: { scope: :registration_id }
end
