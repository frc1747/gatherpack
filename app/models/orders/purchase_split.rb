# What purchases cost, line by line, with shipping and tax shared out in
# proportion to the lines' cost (Purchase#extras_shares, spec §3.5). Reports
# group these rows by vendor, team, month or funding source.
#
#   rows = Orders::PurchaseSplit.rows(Purchase.includes(:vendor, order_lines: :order_request))
#   Orders::PurchaseSplit.totals(rows, by: :team_id)   # { team id => Total }
#   Orders::PurchaseSplit.new(purchase).by_request     # { request id => Total }
module Orders
  class PurchaseSplit
    Row = Struct.new(:purchase, :order_line, :order_request_id, :team_id, :funding_source_id, :vendor_id,
      :vendor_name, :ordered_on, :cost_cents, :extras_cents, keyword_init: true) do
      def total_cents
        cost_cents + extras_cents
      end

      def month
        ordered_on&.beginning_of_month
      end
    end

    Total = Struct.new(:cost_cents, :extras_cents) do
      def total_cents
        cost_cents + extras_cents
      end
    end

    def self.rows(purchases)
      purchases.flat_map { |purchase| new(purchase).rows }
    end

    # Sums rows grouped by a Row attribute (or a block), as { key => Total }.
    def self.totals(rows, by: nil, &block)
      key = block || by.to_proc
      rows.group_by(&key).transform_values do |members|
        Total.new(members.sum(&:cost_cents), members.sum(&:extras_cents))
      end
    end

    attr_reader :purchase

    def initialize(purchase)
      @purchase = purchase
    end

    def rows
      @rows ||= begin
        shares = purchase.extras_shares
        purchase.bought_lines.map do |line|
          Row.new(purchase: purchase, order_line: line, order_request_id: line.order_request_id,
            team_id: line.order_request.team_id, funding_source_id: line.effective_funding_source_id,
            vendor_id: purchase.vendor_id, vendor_name: purchase.vendor_name, ordered_on: purchase.ordered_on,
            cost_cents: line.cost_cents, extras_cents: shares.fetch(line.id, 0))
        end
      end
    end

    def by_request
      self.class.totals(rows, by: :order_request_id)
    end
  end
end
