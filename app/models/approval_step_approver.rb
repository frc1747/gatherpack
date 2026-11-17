# Who approves on an ApprovalStep: holders of a badge, for a team and the
# teams below it, or for every team when team is blank. Only badges admins
# assign count (Orders::Reach).
class ApprovalStepApprover < ApplicationRecord
  has_neat_id :apsa
  has_paper_trail versions: { class_name: "AuditLog" }

  belongs_to :approval_step, inverse_of: :approvers
  belongs_to :badge
  belongs_to :team, optional: true

  validates :badge_id, uniqueness: { scope: %i[approval_step_id team_id] }

  # "Badge > Team", or the badge alone for every team: how the approvers
  # read on screen and in the old setting.
  def line
    [ badge&.name, team&.name ].compact.join(" > ")
  end
end
