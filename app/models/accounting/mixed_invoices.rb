# The invoices a rule counts that also hold items it doesn't filter for.
# Payments and credits apply to a whole invoice, not a line, so a rule
# counts the whole invoice when any line matches its item filter; an
# invoice mixing dues and travel puts the travel money into the dues rule.
# Reads the copied records' item_ids only (no source calls), and names the
# other items from the copied item records. A rule with no item filter, or
# one that reads no invoices, never has any.
class Accounting::MixedInvoices
  LINE_ROLES = %w[ charge receipt ].freeze

  # One counted invoice: its record, the customer's name and the names of
  # the items on it that the rule's filter doesn't list.
  Finding = Data.define(:record, :customer_name, :other_item_names)

  attr_reader :rule

  def initialize(rule)
    @rule = rule
  end

  def findings
    @findings ||= begin
      records = mixed_records.to_a
      other_ids = records.flat_map { |record| record.item_ids - filter.items }.uniq
      items = source_records.where(role: "item", external_id: other_ids).pluck(:external_id, :name).to_h
      customers = source_records.where(role: "customer", customer_external_id: records.map(&:customer_external_id).uniq)
        .pluck(:customer_external_id, :name).to_h
      records.map do |record|
        names = (record.item_ids - filter.items).map { |id| items[id].presence || "Unnamed item" }.uniq.sort
        Finding.new(record: record, customer_name: customers[record.customer_external_id], other_item_names: names)
      end
    end
  end

  def any?
    findings.any?
  end

  def count
    findings.size
  end

  # Every distinct other item's name, sorted, for the warning's sentence.
  def other_item_names
    findings.flat_map(&:other_item_names).uniq.sort
  end

  private
    def filter
      @filter ||= Accounting::RecordFilter.new(rule.filters)
    end

    def source_records
      rule.gateway.accounting_records.current
    end

    def roles
      @roles ||= filter.roles(rule.read_roles) & LINE_ROLES
    end

    # The counted invoices of linked customers whose items stray outside
    # the filter's.
    def mixed_records
      return AccountingRecord.none if filter.items.empty? || roles.empty? || rule.kind == "custom"

      counted = filter.apply(source_records.where(role: roles, voided: false,
        customer_external_id: Accounting::CustomerLinks.new(rule.gateway).linked_customer_ids))
      counted.where.not("accounting_records.item_ids <@ ARRAY[?]::varchar[]", filter.items)
        .order(:txn_date, :number, :external_id)
    end
end
