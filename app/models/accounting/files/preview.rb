# What applying an upload would do to its file source's records: the rows
# it would add, change and remove.
class Accounting::Files::Preview
  Row = Data.define(:change, :role, :label, :customer, :total_cents)
  CHANGES = %w[ add change remove ].freeze

  attr_reader :source, :upload

  def initialize(source, upload)
    @source = source
    @upload = upload
  end

  # Every change, adds first, then changes, then removes.
  def rows
    @rows ||= source.entity_types.keys.flat_map { |entity_type| rows_for(entity_type) }.sort_by { |row| CHANGES.index(row.change) }
  end

  def count(change)
    rows.count { |row| row.change == change }
  end

  private
    def rows_for(entity_type)
      incoming = Array(upload.parsed_records[entity_type]).index_by { |raw| source.external_id(entity_type, raw) }
      current = source.accounting_records.current.where(entity_type: entity_type).index_by(&:external_id)

      found = incoming.filter_map do |external_id, raw|
        record = current[external_id]
        next if record && record.revision == source.revision(entity_type, raw)

        columns = source.normalize(entity_type, raw)
        Row.new(change: record ? "change" : "add", role: columns[:role], label: columns[:public_label].presence || columns[:name],
          customer: customer_label(columns[:customer_external_id]), total_cents: columns[:total_cents])
      end
      found + (current.keys - incoming.keys).map do |external_id|
        record = current[external_id]
        Row.new(change: "remove", role: record.role, label: record.identifier_name,
          customer: customer_label(record.customer_external_id), total_cents: record.total_cents)
      end
    end

    def customer_label(customer_external_id)
      return nil if customer_external_id.nil?

      @customer_labels ||= Array(upload.parsed_records["customer"]).to_h { |raw| [ raw["id"], raw["label"] ] }
        .reverse_merge(source.accounting_records.where(role: "customer").pluck(:customer_external_id, :name).to_h)
      @customer_labels.fetch(customer_external_id, customer_external_id)
    end
end
