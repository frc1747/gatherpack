# What the inventory managers' daily digest reports (inventory spec §3.12,
# §3.15 Notices) for changes since a time: items that went onto the reorder
# list (when inventory_reorder_notice is "daily"), counts that changed
# stock by more than half, and units marked Needs repair or Broken.
# Worked out once for every team; #for_teams narrows it to one manager's.
module Inventory
  class Digest
    Row = Struct.new(:item, :total, keyword_init: true)

    attr_reader :since, :running_low, :count_differences, :needs_repair

    def initialize(since:, now: Time.current, running_low: nil, count_differences: nil, needs_repair: nil)
      @since = since
      @now = now
      @running_low = running_low || (Inventory::Config.reorder_notice.in?(%w[daily weekly]) ? find_running_low : [])
      @count_differences = count_differences || find_count_differences
      @needs_repair = needs_repair || find_needs_repair
    end

    def for_teams(team_ids)
      team_ids = team_ids.to_set
      self.class.new(since: since, now: @now,
        running_low: running_low.select { |row| team_ids.include?(row.item.team_id) },
        count_differences: count_differences.select { |movement| team_ids.include?(movement.item.team_id) },
        needs_repair: needs_repair.select { |unit| team_ids.include?(unit.item.team_id) })
    end

    def empty?
      running_low.empty? && count_differences.empty? && needs_repair.empty?
    end

    def summary
      [
        (pluralize(running_low.size, "item") + " running low" if running_low.any?),
        (pluralize(count_differences.size, "count") + " changed a lot" if count_differences.any?),
        (pluralize(needs_repair.size, "unit") + " to repair" if needs_repair.any?)
      ].compact.join(", ")
    end

    private

    def window
      since..@now
    end

    def pluralize(count, word)
      "#{count} #{count == 1 ? word : word.pluralize}"
    end

    # On the reorder list now and not when the window began. A counted
    # item's total then is worked back from the movements since; a tracked
    # item counts when its units changed in the window.
    def find_running_low
      counted_ids = StockMovement.where(created_at: window).distinct.pluck(:item_id)
      tracked_ids = ItemUnitEvent.where(created_at: window).joins(:item_unit).distinct.pluck("item_units.item_id")
      items = Item.active.where.not(reorder_point: nil).where(id: counted_ids + tracked_ids).to_a
      return [] if items.empty?

      totals = Inventory::Stock.totals(items)
      ordered = Inventory.extensions.on_order(items)
      items.filter_map do |item|
        on_order = ordered[item.id].to_i
        next unless item.on_reorder_list?(totals[item.id], on_order)
        next if !item.tracked? && item.on_reorder_list?(total_at_start(item), on_order)

        Row.new(item: item, total: totals[item.id])
      end.sort_by { |row| row.item.name.downcase }
    end

    def total_at_start(item)
      since_then = StockMovement.where(item_id: item.id, created_at: window).group(:location_id).sum(:quantity)
      StockLevel.joins(:location).merge(Location.active).where(item_id: item.id).sum do |level|
        [ level.quantity - since_then[level.location_id].to_i, 0 ].max
      end
    end

    # Counts (not undone, not undos) whose difference is more than half of
    # what was there before; any difference when nothing was.
    def find_count_differences
      StockMovement.counted.where(created_at: window, reverses_id: nil).where.not(quantity: 0)
        .where.not(id: StockMovement.where.not(reverses_id: nil).select(:reverses_id))
        .includes(:item, :person, :location).order(:created_at).select do |movement|
          before = movement.counted_quantity - movement.quantity
          before <= 0 || movement.quantity.abs * 2 > before
        end
    end

    # Units that became Needs repair or Broken in the window and still are.
    def find_needs_repair
      attention = UnitCondition.attention.select(:id)
      unit_ids = ItemUnitEvent.where(created_at: window, condition_after_id: attention)
        .where.not(condition_before_id: attention).distinct.pluck(:item_unit_id)
      ItemUnit.active.flagged.where(id: unit_ids).includes(:item).order(:code).to_a
    end
  end
end
