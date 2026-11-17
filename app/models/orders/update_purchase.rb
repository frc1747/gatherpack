# A buyer's later changes to a recorded purchase: order number, dates,
# tracking, shipping and tax, paid with, note, more receipts.
#
#   Orders::UpdatePurchase.new(purchase, { expected_on: date }, by: buyer).call
#
# Its requests are locked while it saves. A changed order or expected date
# goes on each request's timeline, since the people who asked can see those;
# the rest is the buyer's business and stays in the audit log.
module Orders
  class UpdatePurchase
    FIELDS = %w[vendor_order_number ordered_on expected_on tracking_url shipping_cents tax_cents paid_with note].freeze
    TIMELINE_FIELDS = %w[ordered_on expected_on].freeze

    attr_reader :purchase, :attributes, :by, :receipts

    def initialize(purchase, attributes, by:, receipts: [])
      @purchase = purchase
      @attributes = attributes.to_h
      @by = by
      @receipts = Array(receipts).compact_blank
    end

    # Returns whether it saved; the purchase carries the errors otherwise.
    def call
      saved = false
      Purchase.transaction do
        requests = OrderRequest.where(id: purchase.order_lines.select(:order_request_id)).order(:id).lock.to_a
        purchase.assign_attributes(attributes)
        changes = purchase.changes.slice(*TIMELINE_FIELDS).transform_values { |pair| pair.map { |value| value&.iso8601 } }
        next unless purchase.save

        purchase.receipts.attach(receipts) if receipts.any?
        if changes.any?
          requests.each do |order_request|
            order_request.log!(:edited, by: by, changes: changes, comment: "Order from #{purchase.vendor_name}")
          end
        end
        saved = true
      end
      saved
    end
  end
end
