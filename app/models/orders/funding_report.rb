require "csv"

# A funding source's report page (spec §3.13): every purchased line charged
# to it, with the approver and the purchase's receipts. Backs a giver's
# report, so it prints and downloads as CSV.
module Orders
  class FundingReport
    Row = Struct.new(:date, :line, :item, :vendor_name, :request, :approver, :cost_cents, :extras_cents, :receipts, keyword_init: true) do
      def total_cents = cost_cents + extras_cents
    end

    HEADERS = [ "Date", "Item", "Quantity", "Store", "Request", "Approved by", "Cost", "Shipping and tax", "Total" ].freeze

    attr_reader :source

    def initialize(source)
      @source = source
    end

    def rows
      @rows ||= begin
        lines = source.order_lines.where.not(purchase_id: nil)
          .includes(:vendor, purchase: [ :vendor, :order_lines, { receipts_attachments: :blob } ], order_request: { order_approvals: :approver }).to_a
        lines.map { |line| row_for(line) }.sort_by { |row| [ row.date || Date.new(0), row.item ] }
      end
    end

    def total_cents
      rows.sum(&:total_cents)
    end

    def to_csv
      CSV.generate do |csv|
        csv << [ Orders::Reports.csv_value(source.name) ]
        csv << HEADERS
        rows.each do |row|
          csv << [ row.date&.iso8601, row.item, row.line.quantity, row.vendor_name, row.request.display_title, row.approver&.display_name,
            cents(row.cost_cents), cents(row.extras_cents), cents(row.total_cents) ].map { |value| Orders::Reports.csv_value(value) }
        end
        csv << [ "Total", nil, nil, nil, nil, nil, nil, nil, cents(total_cents) ]
      end
    end

    private

    def row_for(line)
      purchase = line.purchase
      request = line.order_request
      approval = request.order_approvals.select { |entry| entry.approved? && entry.cleared_at.nil? }.max_by(&:created_at)
      Row.new(date: purchase.ordered_on, line: line, item: line.display_name, vendor_name: purchase.vendor_name || "Unknown",
        request: request, approver: approval&.approver, cost_cents: line.cost_cents,
        extras_cents: purchase.extras_shares.fetch(line.id, 0), receipts: purchase.receipts)
    end

    def cents(value)
      format("%.2f", value / 100.0)
    end
  end
end
