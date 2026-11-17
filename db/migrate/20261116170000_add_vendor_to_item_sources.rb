# Links an item's source to an orders vendor (orders spec §5), so a line
# made from the item picks that vendor. Existing sources are matched once,
# by vendor name and then by the domain of the source's link.
class AddVendorToItemSources < ActiveRecord::Migration[8.1]
  class Vendor < ActiveRecord::Base
    self.table_name = "vendors"
  end

  class ItemSource < ActiveRecord::Base
    self.table_name = "item_sources"
  end

  def change
    add_reference :item_sources, :vendor, type: :uuid, null: true, foreign_key: { on_delete: :nullify }

    up_only { link_existing_sources }
  end

  private

  def link_existing_sources
    vendors = Vendor.where(active: true).order(:name).to_a
    by_name = vendors.reverse.index_by { |vendor| vendor.name.to_s.strip.downcase }

    ItemSource.where(vendor_id: nil).find_each do |source|
      vendor = by_name[source.vendor_name.to_s.strip.downcase] || vendor_for_url(vendors, source.url)
      source.update_columns(vendor_id: vendor.id) if vendor
    end
  end

  def vendor_for_url(vendors, url)
    host = URI.parse(url.to_s.strip).host&.downcase&.delete_prefix("www.")
    return nil if host.nil?

    parts = host.split(".")
    candidates = parts.each_index.map { |index| parts.drop(index).join(".") }
    vendors.find { |vendor| (Array(vendor.domains) & candidates).any? }
  rescue URI::InvalidURIError
    nil
  end
end
