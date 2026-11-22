# Words and links for purchases. On buyer screens a purchase is an "Order"
# (spec §3.16).
module Orders
  module PurchasesHelper
    # Where the given items of a purchase stand, in the line status words:
    # "Here", "Delayed", "Ordered: 1 of 3 here".
    def purchase_status_text(lines)
      live = lines.reject(&:cancelled?)
      return lines.any? ? "Cancelled" : "Ordered" if live.empty?
      return "Here" if live.all?(&:received?)
      return "Problem with delivery" if live.any?(&:problem?)
      return "Needs re-approval" if live.any?(&:needs_reapproval?)
      return "Delayed" if live.any?(&:backordered?)

      here = live.count(&:received?)
      here.positive? || live.any?(&:partly_received?) ? "Ordered: #{here} of #{live.size} here" : "Ordered"
    end

    # A link out to a URL people typed, only when it's http(s).
    def orders_external_link(text, url, **options)
      return text if url.blank? || !url.to_s.match?(%r{\Ahttps?://}i)

      link_to text, url, target: "_blank", rel: "noopener noreferrer", **options
    end

    def orders_money(cents)
      cents.nil? ? "—" : Money.new(cents).format
    end

    # Price as typed into a price box: "12.50".
    def orders_price_value(cents)
      format("%.2f", cents / 100.0) if cents
    end

    # The item actions a buyer may take on the line now.
    def buyer_line_actions(line)
      actions = []
      actions << :backorder if line.ordered? || line.partly_received?
      actions << :change_quantity if line.approved? || line.ordered? || line.backordered? || line.needs_reapproval?
      actions << :split if line.approved? && line.purchase_id.nil?
      actions << :cancel unless line.cancelled? || line.received? || line.problem? || line.pending?
      actions
    end
  end
end
