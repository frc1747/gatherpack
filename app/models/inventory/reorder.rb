# The reorder list (inventory spec §3.5): active items within the person's
# managed reach whose total stock plus on order is at or below the reorder
# point, with the suggested quantity, grouped by the preferred source's
# vendor name ("No source yet" first), out of stock first in each group.
module Inventory
  class Reorder
    NO_SOURCE = "No source yet"

    Row = Struct.new(:item, :total, :on_order, :suggested_quantity, :source, keyword_init: true) do
      def out_of_stock?
        total.zero?
      end

      def vendor_name
        source&.vendor_name.presence || NO_SOURCE
      end
    end

    attr_reader :person, :team_id, :category

    def initialize(person, team_id: nil, category: nil)
      @person = person
      @team_id = team_id.presence
      @category = category.presence
    end

    def allowed?
      Inventory::Access.for(person).manager?
    end

    def items
      access = Inventory::Access.for(person)
      return Item.none unless allowed?

      scope = Item.active.where.not(reorder_point: nil).includes(:item_sources)
      scope = scope.where(team_id: access.managed_team_ids.to_a) unless access.admin?
      scope = scope.where(team_id: team_id) if team_id
      scope = scope.where(category: category) if category
      scope
    end

    def rows
      @rows ||= begin
        items = self.items.to_a
        totals = Inventory::Stock.totals(items)
        ordered = Inventory.extensions.on_order(items)
        items.filter_map do |item|
          total = totals[item.id]
          on_order = ordered[item.id].to_i
          next unless item.on_reorder_list?(total, on_order)

          Row.new(item: item, total: total, on_order: on_order, suggested_quantity: item.suggested_quantity(total, on_order),
            source: item.preferred_source)
        end
      end
    end

    # [[vendor name, rows], ...] with "No source yet" first, then by name.
    def groups
      rows.group_by(&:vendor_name)
        .sort_by { |name, _rows| [ name == NO_SOURCE ? 0 : 1, name.downcase ] }
        .map { |name, rows| [ name, rows.sort_by { |row| [ row.out_of_stock? ? 0 : 1, row.item.name.downcase ] } ] }
    end

    def any?
      rows.any?
    end
  end
end
