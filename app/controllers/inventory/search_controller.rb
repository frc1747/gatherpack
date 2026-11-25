# Inventory home: a search box, and each result with where it is and how
# many (spec §3.9 "Find something").
module Inventory
  class SearchController < BaseController
    RESULTS = 50

    # GET /inventory
    def index
      authorize :inventory, :use?
      skip_policy_scope
      @query = params[:q].to_s.strip
      return @items = [] if @query.empty?

      @items = Item.search(@query, viewer: current_person).includes(:item_sources).limit(RESULTS).to_a
      @totals = Inventory::Stock.totals(@items)
      @levels = StockLevel.where(item_id: @items.map(&:id)).where.not(quantity: 0)
        .where(location_id: policy_scope(Location).active.select(:id)).includes(:location).group_by(&:item_id)
      @places = policy_scope(Location).index_by(&:id)
    end
  end
end
