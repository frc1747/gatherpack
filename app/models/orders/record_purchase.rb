# Records a purchase: the buyer ticked approved lines (from any requests,
# one vendor) and says what the vendor's checkout said.
#
#   Orders::RecordPurchase.new(buyer:, lines:, vendor: vendor, prices: { line.id => 1299 },
#     attributes: { vendor_order_number: "A-1", shipping_cents: 800, paid_with: "Team card" }).call
#
# "Not sure" lines take the purchase's vendor. Every request involved is
# locked (in id order, so two buyers can't deadlock), and its lines are read
# again under the lock, so a line already on another purchase is refused.
# A price that raises a request's total past the tolerance sends the lines
# that rose back for re-approval.
module Orders
  class RecordPurchase
    attr_reader :buyer, :line_ids, :vendor, :other_vendor_name, :prices, :attributes, :receipts

    def initialize(buyer:, lines:, vendor: nil, other_vendor_name: nil, prices: {}, attributes: {}, receipts: [])
      @buyer = buyer
      @line_ids = Array(lines).map { |line| line.respond_to?(:id) ? line.id : line }.uniq
      @vendor = vendor
      @other_vendor_name = other_vendor_name.presence
      @prices = prices.to_h.transform_keys(&:to_s)
      @attributes = attributes.to_h
      @receipts = Array(receipts).compact_blank
    end

    def call
      raise Orders::Refused, "Tick at least one item." if line_ids.empty?

      Purchase.transaction do
        requests = OrderRequest.where(id: OrderLine.where(id: line_ids).select(:order_request_id)).order(:id).lock.to_a
        lines = OrderLine.where(id: line_ids).includes(:order_request).order(:id).to_a
        raise Orders::Refused, "Some of those items no longer exist." if lines.size != line_ids.size

        check(lines)
        purchase = Purchase.create!(attributes.merge(vendor: vendor, other_vendor_name: vendor ? nil : other_vendor_name, buyer: buyer))
        purchase.receipts.attach(receipts) if receipts.any?

        requests.each do |order_request|
          own = lines.select { |line| line.order_request_id == order_request.id }
          own.each { |line| buy(order_request, line, purchase) }
          order_request.order_lines.reset
          order_request.refresh_status_from_lines
          order_request.check_price_tolerance(own, by: buyer)
        end
        purchase
      end
    end

    private

    def check(lines)
      access = Orders::Access.for(buyer)
      lines.each do |line|
        unless access.buyer_for?(line.order_request.team_id)
          raise Orders::Refused, "#{line.display_name} is for #{line.order_request.team.name}, which you don't buy for."
        end
        raise Orders::Refused, "#{line.display_name} is already on an order." if line.purchase_id.present?
        raise Orders::Refused, "#{line.display_name} isn't waiting for a buyer." unless line.approved?
        raise Orders::Refused, "#{line.display_name} is from another vendor." unless same_vendor?(line)
      end
    end

    def same_vendor?(line)
      case line.vendor_choice
      when :not_sure then true
      when :vendor then vendor.present? && line.vendor_id == vendor.id
      when :other then vendor.present? || other_vendor_name.to_s.casecmp?(line.other_vendor_name)
      end
    end

    def buy(order_request, line, purchase)
      line.remember_cost
      price = prices.fetch(line.id.to_s, line.actual_unit_price_cents || line.estimated_unit_price_cents)
      before = line.attributes.slice("vendor_id", "other_vendor_name", "actual_unit_price_cents")
      line.vendor = vendor if vendor && line.vendor_choice != :vendor
      line.other_vendor_name = other_vendor_name if vendor.nil? && line.not_sure?
      line.update!(purchase: purchase, status: :ordered, actual_unit_price_cents: price)
      changes = { "status" => %w[approved ordered] }
      before.each { |field, value| changes[field] = [ value, line[field] ] unless line[field] == value }
      order_request.log!(:purchased, by: buyer, line: line, changes: changes)
    end
  end
end
