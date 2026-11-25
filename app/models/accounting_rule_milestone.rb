# What a balance rule expects paid by a date (Accounting::MilestoneLimit).
# No hooks: a settings row, whose changes show in the audit log with its
# rule.
class AccountingRuleMilestone < ApplicationRecord
  has_neat_id :arm
  has_paper_trail versions: { class_name: "AuditLog" }
  include Accounting::MilestoneLimit

  belongs_to :rule, class_name: "AccountingRule", inverse_of: :milestones
end
