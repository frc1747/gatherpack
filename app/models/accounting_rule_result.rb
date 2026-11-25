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

  # The rule's (or the person's plan's) own milestones, each met or not. A
  # rule without any works from each invoice's due date instead, and those
  # per-invoice checks aren't listed here.
  def milestones
    Array(detail(:milestones)).reject { |milestone| milestone["key"].to_s.start_with?(Accounting::Kinds::Balance::CHARGE_KEY_PREFIX) }
  end

  def milestones?
    milestones.any?
  end

  def unapplied_credit_cents
    detail(:unapplied_credit_cents).to_i
  end

  def on_plan?
    detail(:on_plan) == true
  end
end
