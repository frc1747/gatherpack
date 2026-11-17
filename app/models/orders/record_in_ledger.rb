# Records a purchase in a ledger (spec §6): one finalized expense entry for
# the purchase total, created by the person recording it, with the
# purchase's receipts copied and metadata["purchase_id"] set. The entry is
# tagged with the linked Budget's ledger tags of the lines' funding source.
# When the lines use more than one funding source, the entry is split into
# a child entry per source (with shipping and tax shared out as in
# Orders::PurchaseSplit), each tagged for its own source.
#
#   Orders::RecordInLedger.new(purchase, ledger: ledger, by: person).call   # => LedgerEntry
module Orders
  class RecordInLedger
    attr_reader :purchase, :ledger, :by

    def initialize(purchase, ledger:, by:)
      @purchase = purchase
      @ledger = ledger
      @by = by
    end

    # Refuses a ledger this person can't record in, before anything is written.
    def self.check!(ledger:, by:)
      raise Orders::Refused, "The ledger is turned off." unless LedgerRecording.ledger_on?
      raise Orders::Refused, "Choose a ledger." if ledger.nil?
      raise Orders::Refused, "You can't add entries to #{ledger.name}." unless LedgerRecording.can_add_to?(by, ledger)
    end

    def call
      self.class.check!(ledger: ledger, by: by)

      Purchase.transaction do
        purchase.lock!
        raise Orders::Refused, "This order is already in the ledger." if purchase.ledger_entry_id.present?

        entry = create_entry(remark: remark, amount_cents: purchase.total_cents, created_by: by.user)
        groups = Orders::PurchaseSplit.new(purchase).rows.group_by(&:funding_source_id)
        sources = FundingSource.includes(budget: :ledger_tags).where(id: groups.keys.compact).index_by(&:id)
        if groups.size > 1
          groups.sort_by { |source_id, _| [ source_id.nil? ? 1 : 0, sources[source_id]&.name.to_s ] }.each do |source_id, rows|
            source = sources[source_id]
            child = create_entry(remark: source&.name || "No funding source", amount_cents: rows.sum(&:total_cents),
              created_by: entry, parent: entry)
            tag(child, source)
          end
        else
          tag(entry, sources[groups.keys.first])
        end
        copy_receipts(entry)
        purchase.update!(ledger_entry: entry)
        entry
      end
    end

    private

    def create_entry(remark:, amount_cents:, created_by:, parent: nil)
      LedgerEntry.create!(ledger: ledger, parent: parent, created_by: created_by, remark: remark,
        amount_cents: -amount_cents, finalized: true, metadata: { "purchase_id" => purchase.id })
    end

    # "Order from Parts Depot #A-1", and for a purchase someone paid for
    # themselves, who to pay back.
    def remark
      text = "Order from #{purchase.vendor_name}"
      text += " ##{purchase.vendor_order_number}" if purchase.vendor_order_number.present?
      text += ", pay back #{purchase.reimburse_to.identifier_name}" if purchase.reimburse? && purchase.reimburse_to
      text
    end

    def tag(entry, source)
      LedgerRecording.tags_for(source).each { |ledger_tag| entry.ledger_taggings.create!(ledger_tag: ledger_tag) }
    end

    # Copies, not shared blobs, so removing a receipt from one side leaves
    # the other's. The purchase's receipts must be stored already: record a
    # new purchase after its transaction commits.
    def copy_receipts(entry)
      purchase.receipts.each do |receipt|
        entry.receipts.attach(io: StringIO.new(receipt.download), filename: receipt.filename.to_s,
          content_type: receipt.content_type)
      end
    end
  end
end
