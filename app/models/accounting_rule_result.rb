# One person's answer to one rule: the value ("paid", "overdue"), the amount
# (a balance's remaining amount), and details (charges, milestones,
# unapplied credit) for the screens. Saved by Accounting::Evaluation only
# when something changed. No hooks: "accounting_rules - result changed" is
# the signal.
class AccountingRuleResult < ApplicationRecord
  has_neat_id :arr

  belongs_to :rule, class_name: "AccountingRule", inverse_of: :results
  belongs_to :person
  belongs_to :badge_assignment, optional: true

  validates :value, presence: true
  validates :person_id, uniqueness: { scope: :rule_id }

  def label
    rule.label_for(value)
  end

  def error?
    value == AccountingRule::ERROR
  end

  def detail(key)
    (details || {})[key.to_s]
  end

  def charges
    Array(detail(:charges))
  end

  def unapplied_credit_cents
    detail(:unapplied_credit_cents).to_i
  end

  def on_plan?
    detail(:on_plan) == true
  end
end
