class Budget < ApplicationRecord
  has_neat_id :bud
  has_paper_trail versions: { class_name: "AuditLog" }
  include CanBeHooked
  belongs_to :budget_period
  has_many :budget_taggings, dependent: :destroy
  has_many :ledger_tags, through: :budget_taggings
  monetize :amount_cents
  monetize :actual_amount_cents
  monetize :remaining_amount_cents

  def identifier_icon
    "wallet"
  end

  def identifier_name
    "#{budget_period.identifier_name} #{ledger_tags.map { |t| t.name.split(":").last }.join(", ")}"
  end

  # Entries in the ledgers of the budget period's own team that carry every
  # one of the budget's tags. Other teams' ledgers, sub-teams' included, may
  # use the same tags, but their money belongs to their own budgets, and the
  # totals have to match what everyone who may see the budget may list.
  def ledger_entries
    return @ledger_entries if @ledger_entries
    tag_ids = ledger_tags.pluck(:id)
    @ledger_entries = LedgerEntry.joins(:ledger_taggings)
      .where(ledger_id: Ledger.where(team_id: budget_period.team_id).select(:id))
      .where(ledger_taggings: { ledger_tag_id: tag_ids })
      .where(ledger_entries: { created_at: budget_period.starts_at..budget_period.ends_at })
      .group("ledger_entries.id")
      .having("COUNT(DISTINCT ledger_taggings.ledger_tag_id) = ?", tag_ids.count)
      .all
  end

  def actual_amount_cents
    @actual_amount_cents ||= ledger_entries.pluck(:amount_cents).reduce(0, :+)
  end

  def remaining_amount_cents
    amount_cents + actual_amount_cents
  end

  def percentage
    return 0 if amount_cents.zero?
    ((-actual_amount_cents.to_f / amount_cents.to_f) * 100).round(2)
  end
end
