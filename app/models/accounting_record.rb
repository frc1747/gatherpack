# One record copied from an accounting source (Accounting::Provider): the
# source's raw data plus the neutral columns its normalize fills, which is
# all the rest of the feature reads. No audit log: the source is the
# history. The sync only saves a record whose revision changed, so record
# hooks fire for real changes only.
class AccountingRecord < ApplicationRecord
  has_neat_id :acr
  include CanBeHooked

  ROLES = %w[ customer charge receipt payment credit refund item category other ].freeze

  # The columns a source's normalize may fill.
  NEUTRAL_COLUMNS = %i[
    role customer_external_id parent_external_id name email reference active number txn_date due_on
    total_cents balance_cents voided lines item_ids class_ids location_ids applied_to unapplied_cents
    pay_url external_url public_label description external_updated_at
  ].freeze

  MONEY_COLUMNS = %i[ total_cents balance_cents unapplied_cents ].freeze

  belongs_to :gateway

  validates :entity_type, :external_id, presence: true
  validates :role, inclusion: { in: ROLES }
  validates(*MONEY_COLUMNS, numericality: { greater_than_or_equal_to: 0, only_integer: true }, allow_nil: true)

  scope :current, -> { where(deleted_at: nil) }

  def self.ransackable_attributes(auth_object = nil)
    %w[ role customer_external_id number txn_date entity_type ]
  end

  def deleted?
    deleted_at.present?
  end

  def identifier_name
    public_label.presence || name.presence || "#{entity_type} #{external_id}"
  end
end
