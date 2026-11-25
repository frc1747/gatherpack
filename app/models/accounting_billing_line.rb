# One person's charge in a billing run (AccountingBillingRun): which of
# their customers it's for, how much, and how it went. request_id is set
# when the line is made and never changes, so writing the charge again
# after a crash or a retry returns the first charge instead of a second
# (Accounting::Provider#create_charge). A created line is never sent again.
#
# No record hooks: "accounting_billing_lines - failed" covers what matters.
class AccountingBillingLine < ApplicationRecord
  has_neat_id :abl
  has_paper_trail versions: { class_name: "AuditLog" }

  STATUSES = %w[ pending created failed skipped exported ].freeze
  STATUS_NAMES = { "pending" => "Waiting", "created" => "Created", "failed" => "Failed", "skipped" => "Skipped", "exported" => "In the CSV" }.freeze
  # Fired with the line when writing its charge failed; error says why.
  FAILED_EVENT = "accounting_billing_lines - failed".freeze

  belongs_to :run, class_name: "AccountingBillingRun", inverse_of: :lines
  belongs_to :person

  before_validation -> { self.request_id ||= SecureRandom.uuid }, on: :create

  validates :status, inclusion: { in: STATUSES }
  validates :amount_cents, numericality: { only_integer: true, greater_than: 0 }
  validates :person_id, uniqueness: { scope: :run_id }
  validate :request_id_unchanged, on: :update

  STATUSES.each do |status|
    scope status, -> { where(status: status) }
    define_method(:"#{status}?") { self.status == status }
  end

  def identifier_icon
    "file-invoice-dollar"
  end

  def identifier_name
    "#{person&.identifier_name}: #{run&.item_name}"
  end

  def status_name
    STATUS_NAMES.fetch(status, status.to_s.humanize)
  end

  # The request id for creating this line's customer: its own, so a source
  # that keys idempotency on the id alone never confuses the customer with
  # the charge, and the same on every retry.
  def customer_request_id
    Digest::UUID.uuid_v5(request_id, "customer")
  end

  # Marks the line failed and fires the failed event.
  def fail!(message)
    update!(status: "failed", error: message.to_s.truncate(500))
    Hook.where(event: FAILED_EVENT).each { |hook| hook.run(self) }
  end

  def skip!(reason)
    update!(status: "skipped", error: reason)
  end

  private
    def request_id_unchanged
      errors.add(:request_id, "can't be changed") if will_save_change_to_request_id?
    end
end
