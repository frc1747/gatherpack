# Which GatherPack person a source's customer is for. Many to many: one
# family customer can be linked to each child, and one person can have
# several customers. Rules only see records whose customer is linked.
class AccountingCustomerLink < ApplicationRecord
  has_neat_id :acl
  include CanBeHooked

  has_paper_trail versions: { class_name: "AuditLog" }

  # How the link was made: an admin confirmed a suggestion, an admin picked
  # the person, an exact reference match linked it automatically, a ledger
  # owner, or billing created the customer.
  SOURCES = %w[ confirmed manual reference ledger_owner created ].freeze

  belongs_to :gateway
  belongs_to :person
  belongs_to :created_by, class_name: "Person", optional: true

  validates :customer_external_id, presence: true
  validates :source, inclusion: { in: SOURCES }
  validates :person_id, uniqueness: { scope: %i[ gateway_id customer_external_id ] }

  # The customer record this link names, if the source has copied it.
  def customer
    AccountingRecord.find_by(gateway_id: gateway_id, role: "customer", customer_external_id: customer_external_id)
  end

  def automatic?
    source.in?(%w[ reference ledger_owner created ])
  end
end
