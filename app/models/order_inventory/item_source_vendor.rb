# Adds the orders vendor to an inventory item source (item_sources.vendor_id),
# picked on the source form. A source saved with a new name or link and no
# vendor picks up a vendor that matches by name or link domain.
module OrderInventory
  module ItemSourceVendor
    extend ActiveSupport::Concern

    included do
      belongs_to :vendor, optional: true
      before_save :match_vendor, if: -> { vendor_id.nil? && (new_record? || will_save_change_to_vendor_name? || will_save_change_to_url?) }
    end

    private

    def match_vendor
      self.vendor = OrderInventory.match_vendor(vendor_name, url)
    end
  end
end
