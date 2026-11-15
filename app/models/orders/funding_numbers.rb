# A funding source's numbers (spec §3.13): what orders has spent on it
# (purchased lines at actual prices plus their share of shipping and tax,
# including lines cancelled after purchase: returns aren't tracked),
# what's committed (approved lines not yet bought, at estimated prices),
# and what remains of its amount after both and anything spent outside
# orders. Lines naming no source count against their request's.
module Orders
  class FundingNumbers
    attr_reader :source

    def initialize(source)
      @source = source
    end

    def spent_cents
      @spent_cents ||= begin
        # A line cancelled after it was bought was still paid for.
        lines = source.order_lines.where.not(purchase_id: nil).to_a
        shares = Purchase.where(id: lines.map(&:purchase_id).uniq).includes(:order_lines).to_a
          .reduce({}) { |all, purchase| all.merge(purchase.extras_shares) }
        lines.sum { |line| line.cost_cents + shares.fetch(line.id, 0) }
      end
    end

    def committed_cents
      @committed_cents ||= source.order_lines.where(purchase_id: nil, status: %i[approved needs_reapproval]).to_a
        .sum { |line| line.quantity * (line.estimated_unit_price_cents || line.actual_unit_price_cents).to_i }
    end

    # Nil when the source has no amount.
    def remaining_cents
      return nil if source.amount_cents.nil?

      source.amount_cents - spent_cents - committed_cents - source.spent_outside_cents.to_i
    end

    # What this request would add: its live lines on this source that
    # aren't counted yet (not yet approved).
    def request_cents(order_request)
      order_request.live_lines.select { |line| line.pending? && line.effective_funding_source_id == source.id }.sum(&:cost_cents)
    end

    # What would remain after the request, or nil with no amount.
    # On a re-approval the items are already counted as committed or spent,
    # so nothing more comes off.
    def remaining_after_cents(order_request)
      return remaining_cents unless order_request.submitted?

      remaining_cents && remaining_cents - request_cents(order_request)
    end

    def over_after?(order_request)
      remaining = remaining_after_cents(order_request)
      !remaining.nil? && remaining.negative?
    end
  end
end
