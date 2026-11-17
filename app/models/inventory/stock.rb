# Stock and reorder arithmetic over many items at once (inventory spec
# §3.4), and the item hook events that fire when a change crosses a line.
module Inventory
  module Stock
    module_function

    # { item_id => total stock }: the sum over active locations with
    # negatives counted as zero, or for a tracked item the units available.
    def totals(items)
      items = Array(items)
      return {} if items.empty?

      tracked, counted = items.partition(&:tracked?)
      totals = {}
      if counted.any?
        totals.merge!(StockLevel.joins(:location).merge(Location.active).where(item_id: counted.map(&:id))
          .group(:item_id).sum(Arel.sql("GREATEST(stock_levels.quantity, 0)")))
      end
      totals.merge!(ItemUnit.available.where(item_id: tracked.map(&:id)).group(:item_id).count) if tracked.any?
      items.to_h { |item| [ item.id, totals[item.id].to_i ] }
    end

    # The item events a change from total before to after crosses, given
    # what's on order: :running_low (onto the reorder list), :out_of_stock
    # (reached zero) and :restocked (back above the reorder point).
    def crossings(item, before, after, ordered = 0)
      events = []
      point = item.reorder_point
      unless point.nil?
        events << :running_low if before + ordered > point && after + ordered <= point
        events << :restocked if before <= point && after > point
      end
      events << :out_of_stock if before.positive? && after.zero?
      events
    end

    # Runs the change in the block with the item locked, so the totals
    # before and after are this change's alone, then calls announce with
    # the crossings and the total after, still inside the transaction (so
    # the records it marks announce them when it commits). Returns the
    # block's result.
    def with_crossings(item, announce:)
      ordered = Inventory.extensions.on_order([ item ])[item.id].to_i
      item.transaction do
        item.lock!
        before = totals([ item ])[item.id]
        result = yield
        after = totals([ item ])[item.id]
        announce.call(crossings(item, before, after, ordered), after)
        result
      end
    end

    # Fires the hooks for crossings once the change has committed, and the
    # immediate notice when inventory_reorder_notice is "each".
    def announce_crossings(item, crossings)
      crossings.each { |event| Inventory.run_hooks(Inventory::ITEM_EVENTS.fetch(event), item) }
      return unless crossings.include?(:running_low) && Inventory.enabled? && Inventory::Config.reorder_notice == "each"

      InventoryNotices.new.running_low(item)
    end
  end
end
