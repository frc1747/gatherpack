# One go at billing people: what to charge (an item and a default amount,
# with dates and a memo) and a line for each person (AccountingBillingLine).
# Started from a rule's Bill people or from Account Status; saved running,
# then Accounting::BillingRunJob writes each line's charge into the source,
# which stays the record: the charges count once they come back through
# the sync like any other record. A source that can't create charges gets
# a CSV in the file source's layout instead, and the run is finished at
# once with its lines exported.
class AccountingBillingRun < ApplicationRecord
  has_neat_id :abr

  STATUSES = %w[ draft running finished ].freeze
  # Fired with the run once no line is pending; details has the counts.
  FINISHED_EVENT = "accounting_billing_runs - finished".freeze

  belongs_to :gateway
  belongs_to :rule, class_name: "AccountingRule", optional: true, inverse_of: :billing_runs
  belongs_to :created_by, class_name: "Person", optional: true
  # Before CanBeHooked, so the lines are saved when the create hook sees
  # the run.
  has_many :lines, -> { order(:created_at, :id) }, class_name: "AccountingBillingLine", foreign_key: :run_id,
    inverse_of: :run, dependent: :delete_all

  include CanBeHooked
  has_paper_trail versions: { class_name: "AuditLog" }

  validates :created_by, presence: true, on: :create
  validates :item_external_id, presence: true
  validates :amount_cents, numericality: { only_integer: true, greater_than: 0 }
  validates :status, inclusion: { in: STATUSES }
  validate :source_is_accounting
  validate :due_after_invoice_date

  scope :newest_first, -> { order(created_at: :desc) }

  def identifier_icon
    "file-invoice-dollar"
  end

  def identifier_name
    "#{item_name} billing, #{I18n.l(created_at.to_date, format: :long)}" if created_at
  end

  def finished?
    status == "finished"
  end

  def capabilities
    gateway.respond_to?(:capabilities) ? gateway.capabilities : Set.new
  end

  # Whether this run writes charges into the source; otherwise it's a CSV.
  def creates_charges?
    capabilities.include?(:create_charges)
  end

  # The item's name from the source's item records.
  def item_name
    gateway.accounting_records.find_by(role: "item", external_id: item_external_id)&.name || item_external_id
  end

  # How many lines are in each status, for the run page and the finished
  # event's hooks.
  def details
    AccountingBillingLine::STATUSES.index_with { 0 }.merge(lines.unscope(:order).group(:status).count)
  end

  # Marks the run finished once no line is pending, and fires the finished
  # event. Returns whether it finished just now.
  def finish_if_done!
    finished = with_lock do
      next false if finished? || lines.pending.exists?

      update!(status: "finished", finished_at: Time.current)
      true
    end
    Hook.where(event: FINISHED_EVENT).each { |hook| hook.run(self) } if finished
    finished
  end

  # Sets failed lines back to pending, with the same request ids, so a
  # retry returns any charge a failed call did create instead of a second.
  def retry_failed!
    transaction do
      lines.failed.update_all(status: "pending", error: nil, updated_at: Time.current)
      update!(status: "running", finished_at: nil)
    end
    Accounting::BillingRunJob.perform_later(self)
  end

  private
    def source_is_accounting
      errors.add(:gateway, "must be an accounting source") if gateway && !gateway.is_a?(Accounting::Provider)
    end

    def due_after_invoice_date
      errors.add(:due_on, "can't be before the invoice date") if due_on && txn_date && due_on < txn_date
    end
end
