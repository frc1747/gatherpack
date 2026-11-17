# Where to buy an item: vendor name, part number and link (spec §3.1).
module Inventory
  class ItemSourcesController < BaseController
    before_action :set_item
    before_action :set_item_source, only: %i[edit update destroy]

    # GET /inventory/items/1/sources/new
    def new
      @item_source = authorize @item.item_sources.build(preferred: @item.item_sources.none?)
    end

    # GET /inventory/items/1/sources/1/edit
    def edit
    end

    # POST /inventory/items/1/sources
    def create
      @item_source = authorize @item.item_sources.build(item_source_params)

      if @item_source.save
        redirect_to inventory_item_path(@item), notice: "Added #{@item_source.vendor_name}."
      else
        render :new, status: :unprocessable_entity
      end
    end

    # PATCH/PUT /inventory/items/1/sources/1
    def update
      if @item_source.update(item_source_params)
        redirect_to inventory_item_path(@item), notice: "Saved #{@item_source.vendor_name}.", status: :see_other
      else
        render :edit, status: :unprocessable_entity
      end
    end

    # DELETE /inventory/items/1/sources/1
    def destroy
      @item_source.destroy!
      redirect_to inventory_item_path(@item), notice: "Removed #{@item_source.vendor_name}.", status: :see_other
    end

    private

    def set_item
      @item = policy_scope(Item).find(params[:item_id])
    end

    def set_item_source
      @item_source = authorize @item.item_sources.find(params[:id])
    end

    def item_source_params
      params.require(:item_source).permit(:vendor_name, :vendor_part_number, :url, :preferred, :note, :position,
        *Inventory.extensions.source_permitted_params)
    end
  end
end
