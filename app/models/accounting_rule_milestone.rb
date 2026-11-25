# What a balance rule expects paid by a date: the balance remaining at most
# an amount, or a percent of what was charged (0 = paid in full). No hooks:
# a settings row, whose changes show in the audit log with its rule.
class AccountingRuleMilestone < ApplicationRecord
  has_neat_id :arm
  has_paper_trail versions: { class_name: "AuditLog" }

  belongs_to :rule, class_name: "AccountingRule", inverse_of: :milestones

  validates :name, :due_on, presence: true
  validates :balance_at_most_cents, numericality: { only_integer: true, greater_than_or_equal_to: 0 }, allow_nil: true
  validates :balance_at_most_percent, numericality: { only_integer: true, in: 0..100 }, allow_nil: true
  validate :one_limit

  # The form's amount in dollars ("150", "150.00").
  def balance_at_most
    balance_at_most_cents && Money.new(balance_at_most_cents).to_s
  end

  def balance_at_most=(text)
    self.balance_at_most_cents = Accounting.parse_cents(text)
  end

  # The most that may be left owing to meet this milestone, given what was
  # charged.
  def limit_cents(charged_cents)
    balance_at_most_cents || (charged_cents * balance_at_most_percent.to_i / 100.0).floor
  end

  def met?(balance_cents, charged_cents)
    balance_cents <= limit_cents(charged_cents)
  end

  private
    def one_limit
      return if balance_at_most_cents.nil? ^ balance_at_most_percent.nil?

      errors.add(:base, "Give the balance at most as an amount or a percent, not both") if balance_at_most_cents && balance_at_most_percent
      errors.add(:base, "Give the balance it may be at most, as an amount or a percent (0 for paid in full)") if balance_at_most_cents.nil? && balance_at_most_percent.nil?
    end
end
