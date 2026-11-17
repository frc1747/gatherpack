# "Create item from this line": an Item's attributes and its first source,
# taken from what was ordered. A line bought in packs (units_per above 1)
# makes an item counted in pieces, in the default stock unit.
module OrderInventory
  module ItemFromLine
    def self.attributes(line)
      unit = line.units_per.to_i > 1 ? nil : StockUnit.active.named(line.unit)
      {
        team: line.order_request.team,
        name: line.description.presence || line.display_name,
        manufacturer: line.manufacturer.presence,
        manufacturer_part_number: line.manufacturer_part_number.presence,
        url: (line.url if line.web_link?)
      }.tap { |values| values[:stock_unit] = unit if unit }
    end

    # The preferred source: the line's store, its part number and link. Nil
    # when the store isn't known ("Not sure").
    def self.source_attributes(line)
      name = OrderInventory.from_name(line)
      return nil if name.blank?

      vendor_id = line.purchase&.vendor_id || line.vendor_id
      { vendor_name: name, vendor_id: vendor_id, vendor_part_number: line.vendor_part_number.presence,
        url: (line.url if line.web_link?), preferred: true }
    end
  end
end
