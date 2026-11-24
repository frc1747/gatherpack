# Turns tracking on or off for an item (inventory spec §3.15). On turns
# the item's stock into units; off is refused while the item has units.
module Inventory
  class ItemTrackingController < BaseController
    before_action :set_item

    def create
      authorize @item, :start_tracking?
      count = @item.stock_levels.where("quantity > 0").sum(:quantity)
      @item.start_tracking!(by: current_user.person)
      message = count.positive? ? "Each piece is now tracked: #{helpers.pluralize(count, "unit")} to label" : "Each piece is now tracked"
      redirect_to inventory_item_path(@item), notice: message, status: :see_other
    end

    def destroy
      authorize @item, :stop_tracking?
      @item.stop_tracking!(by: current_user.person)
      redirect_to inventory_item_path(@item), notice: "Tracking turned off", status: :see_other
    end

    private

    def set_item
      @item = policy_scope(Item).find(params[:item_id])
    end
  end
end
