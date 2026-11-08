class LedgerTransfer
  include ActiveModel::Model
  include ActiveModel::Attributes

  attribute :from_ledger_id, :string
  attribute :to_ledger_id, :string
  attribute :amount, :decimal
  attribute :creator_id, :string
  attribute :creator_type, :string

  validates :from_ledger, :to_ledger, presence: true
  validates :amount, numericality: { greater_than: 0 }
  validate :different_ledgers

  def from_ledger
    Ledger.find_by(id: from_ledger_id) if from_ledger_id.present?
  end

  def to_ledger
    Ledger.find_by(id: to_ledger_id) if to_ledger_id.present?
  end

  def creator
    creator_type.constantize.find(creator_id)
  end

  def creator=(obj)
    self.creator_type = obj.class.to_s
    self.creator_id = obj.id
  end

  def create
    return false unless valid?

    LedgerEntry.transaction do
      t = LedgerEntry.create!(ledger: from_ledger, amount: amount, remark: "Transfer to #{to_ledger.name}", created_by: creator, transfer_mirror: true)
      f = LedgerEntry.create!(ledger: to_ledger, amount: amount, remark: "Transfer from #{from_ledger.name}", created_by: creator)

      LedgerEntryLink.create!(ledger_entries: [ t, f ])
    end
  end

  private

  def different_ledgers
    errors.add(:to_ledger_id, "must be a different ledger") if from_ledger.present? && from_ledger == to_ledger
  end
end
