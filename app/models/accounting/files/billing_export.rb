require "csv"

# A billing run as a CSV in the file source's layout
# (Accounting::Files::Template), for a source GatherPack can't write
# charges into: one charge row per exported line, its number left blank
# for the accounting program to assign, to import there. The next upload
# brings the charges back.
class Accounting::Files::BillingExport
  attr_reader :run

  def initialize(run)
    @run = run
  end

  def csv
    CSV.generate do |csv|
      csv << Accounting::Files::Template::COLUMNS
      run.lines.exported.includes(:person).each { |line| csv << row(line) }
    end
  end

  def filename
    "billing-#{run.item_name.parameterize.presence || 'charges'}-#{run.created_at.to_date.iso8601}.csv"
  end

  private
    def row(line)
      cells = {
        "customer" => customer_names.fetch(line.customer_external_id, line.customer_external_id),
        "role" => "charge",
        "number" => nil,
        "date" => run.txn_date&.iso8601,
        "due_date" => run.due_on&.iso8601,
        "item" => run.item_name,
        "total" => format("%.2f", line.amount_cents / 100.0),
        "balance" => nil,
        "applied_to" => nil,
        "description" => run.memo.presence
      }
      cells.values_at(*Accounting::Files::Template::COLUMNS)
    end

    # The customers' names as the source copied them, so the file reads
    # back to the same customers.
    def customer_names
      @customer_names ||= run.gateway.accounting_records.where(role: "customer", customer_external_id: run.lines.map(&:customer_external_id))
        .pluck(:customer_external_id, :name).to_h.compact_blank
    end
end
