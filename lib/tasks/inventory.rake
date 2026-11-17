namespace :inventory do
  desc "Rebuild the stock_levels cache from the stock movements and report each difference found"
  task rebuild_stock_levels: :environment do
    differences = Inventory::StockLevels.rebuild!(fix: true)
    if differences.empty?
      puts "Stock levels match the movements."
    else
      differences.each do |difference|
        item = Item.find_by(id: difference.item_id)
        location = Location.find_by(id: difference.location_id)
        puts "#{item&.name || difference.item_id} at #{location&.full_name || difference.location_id}: " \
          "was #{difference.cached.inspect}, now #{difference.actual}"
      end
      puts "Fixed #{differences.size} stock #{differences.size == 1 ? "level" : "levels"}."
    end
  end
end
