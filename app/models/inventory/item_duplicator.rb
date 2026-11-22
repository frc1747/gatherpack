# Copies an item for the person who wants a similar one (inventory spec
# §3.1): its own fields, named "<name> (copy)", its reading types and
# where to buy it. Stock, stock movements and units stay with the original.
module Inventory
  class ItemDuplicator
    COPIED = %w[team_id description category manufacturer manufacturer_part_number tracked home_location_id
      reorder_point reorder_quantity url note active stock_unit_id].freeze

    def self.call(item)
      new(item).call
    end

    def initialize(item)
      @item = item
    end

    def call
      Item.transaction do
        copy = Item.new(@item.attributes.slice(*COPIED))
        copy.name = "#{@item.name} (copy)"
        @item.item_reading_types.each do |row|
          copy.item_reading_types.build(reading_type_id: row.reading_type_id, position: row.position)
        end
        copy.save!
        @item.item_sources.each do |source|
          copy.item_sources.create!(source.attributes.slice("vendor_name", "vendor_part_number", "url", "preferred", "note", "position"))
        end
        copy
      end
    end
  end
end
