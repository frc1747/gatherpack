# The readings a check asks for on a tracked item (inventory spec §3.15):
# each a name and a unit, such as "Run time" in "h".
module Inventory
  class ItemReadingsController < BaseController
    # Blank rows offered under the item's readings, for adding new ones.
    BLANK_ROWS = 3

    before_action :set_item

    def edit
    end

    def update
      if @item.update(reading_fields: reading_fields_params)
        redirect_to inventory_item_path(@item), notice: "Readings saved", status: :see_other
      else
        render :edit, status: :unprocessable_entity
      end
    end

    private

    def set_item
      @item = authorize policy_scope(Item).find(params[:item_id]), :update?
    end

    def reading_fields_params
      params.fetch(:item, {}).permit(reading_fields: %i[name unit]).fetch(:reading_fields, []).map(&:to_h)
    end
  end
end
