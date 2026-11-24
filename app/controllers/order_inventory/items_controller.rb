# The item search behind Pick from what we stock and the receive dialog's
# "Which item is it?": items the viewer sees, as JSON.
module OrderInventory
  class ItemsController < BaseController
    LIMIT = 10

    # GET /order_inventory/items.json?q=
    def index
      items = policy_scope(Item).search(params[:q], viewer: current_user.person)
        .includes(:item_sources, stock_levels: :location).limit(LIMIT).to_a
      totals = Inventory::Stock.totals(items)
      render json: items.map { |item| item_json(item, totals[item.id].to_i) }
    end

    private

    def item_json(item, total)
      line = OrderInventory.line_attributes(item)
      vendor_choice = line[:vendor_id] || (line[:other_vendor_name].present? ? "other" : "not_sure")
      {
        id: item.id,
        name: item.name,
        part_number: item.manufacturer_part_number,
        stock: "#{total} #{item.unit}",
        unit: item.unit,
        vendor_name: line[:vendor_id] ? Vendor.find_by(id: line[:vendor_id])&.name : line[:other_vendor_name],
        tracked: item.tracked?,
        line: line.except(:item, :vendor_id).merge(vendor_choice: vendor_choice, item_type: "Item", item_id: item.id)
      }
    end
  end
end
