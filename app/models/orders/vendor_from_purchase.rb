# Turns a purchase's "Other store" name into a vendor record (spec §3.5):
# an existing vendor of that name (any case) when there is one, otherwise a
# new one. The purchase and its items from that store take the vendor, and
# each request's timeline says so. Returns the vendor.
#
#   Orders::VendorFromPurchase.new(purchase, by: buyer).call
module Orders
  class VendorFromPurchase
    attr_reader :purchase, :by

    def initialize(purchase, by:)
      @purchase = purchase
      @by = by
    end

    def call
      raise Orders::Refused, "This order already has a vendor." if purchase.vendor_id.present?

      name = purchase.other_vendor_name.to_s.squish
      raise Orders::Refused, "This order has no store name to make a vendor from." if name.blank?

      Purchase.transaction do
        requests = OrderRequest.where(id: purchase.order_lines.select(:order_request_id)).order(:id).lock.index_by(&:id)
        vendor = Vendor.where("LOWER(name) = ?", name.downcase).first || Vendor.create!(name: name)
        purchase.update!(vendor: vendor, other_vendor_name: nil)
        purchase.order_lines.where(vendor_id: nil).find_each do |line|
          before = line.other_vendor_name
          line.update!(vendor: vendor)
          requests.fetch(line.order_request_id).log!(:edited, by: by, line: line, changes: { "vendor" => [ before, vendor.name ] })
        end
        vendor
      end
    end
  end
end
