# One row of a person's payment plan for a balance rule: their own
# milestone (Accounting::MilestoneLimit). Any plan rows for a person replace
# all of the rule's milestones for that person (AccountingRule#milestones_for);
# removing the last returns them to the rule's.
#
# The plan's names, dates and amounts show to the person, their guardians
# and admins (Accounting::RuleAccess#sees_plan?); leaders and badge-grant
# holders see only the status, since a plan can reveal hardship. Only admins
# see that a person is on a plan, and the note.
class AccountingPersonMilestone < ApplicationRecord
  has_neat_id :apm
  include CanBeHooked
  has_paper_trail versions: { class_name: "AuditLog" }
  include Accounting::MilestoneLimit

  belongs_to :rule, class_name: "AccountingRule", inverse_of: :person_milestones
  belongs_to :person
  belongs_to :created_by, class_name: "Person", optional: true

  validate :balance_rule

  scope :ordered, -> { order(:due_on, :position, :created_at) }

  def identifier_icon
    "file-invoice-dollar"
  end

  def identifier_name
    "#{rule&.name}: #{person&.identifier_name} #{name}"
  end

  private
    def balance_rule
      errors.add(:rule, "must be a balance rule to have a payment plan") if rule && !rule.balance?
    end
end
