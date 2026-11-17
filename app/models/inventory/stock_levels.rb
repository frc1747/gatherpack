# Rebuilds the stock_levels cache from the movements, which are the
# record, and reports each difference found (rake
# inventory:rebuild_stock_levels).
module Inventory
  module StockLevels
    Difference = Struct.new(:item_id, :location_id, :cached, :actual, keyword_init: true)

    module_function

    # The differences between the cache and the movements; with fix: true,
    # the cache is corrected (each pair under its row lock).
    def rebuild!(fix: true)
      actual = StockMovement.group(:item_id, :location_id).sum(:quantity)
      cached = StockLevel.pluck(:item_id, :location_id, :quantity).to_h { |item_id, location_id, quantity| [ [ item_id, location_id ], quantity ] }

      differences = (actual.keys | cached.keys).filter_map do |pair|
        next if actual[pair].to_i == cached[pair].to_i

        Difference.new(item_id: pair[0], location_id: pair[1], cached: cached[pair], actual: actual[pair].to_i)
      end
      differences.each { |difference| correct!(difference) } if fix
      differences
    end

    def correct!(difference)
      StockLevel.transaction do
        item = Item.find(difference.item_id)
        location = Location.find(difference.location_id)
        level = StockLevel.locked_for(item, location)
        level.update!(quantity: StockMovement.where(item_id: item.id, location_id: location.id).sum(:quantity))
      end
    end
  end
end
