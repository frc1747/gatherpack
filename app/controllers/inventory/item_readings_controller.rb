# The readings a check asks for on a tracked item (inventory spec §3.15):
# reading types picked from the list managed on Setup, such as Hours (h).
module Inventory
  class ItemReadingsController < BaseController
    before_action :set_item

    def edit
    end

    def update
      @item.reading_type_ids = reading_type_ids_params
      if @item.save
        redirect_to inventory_item_path(@item), notice: "Readings saved", status: :see_other
      else
        render :edit, status: :unprocessable_entity
      end
    end

    private

    def set_item
      @item = authorize policy_scope(Item).find(params[:item_id]), :update?
    end

    # Only types offered on the form: active ones, and retired ones the item
    # already tracks.
    def reading_type_ids_params
      ids = Array(params.dig(:item, :reading_type_ids)).compact_blank.map(&:to_s)
      offered = ReadingType.active.or(ReadingType.where(id: @item.reading_type_ids)).where(id: ids).pluck(:id)
      ids & offered
    end
  end
end
