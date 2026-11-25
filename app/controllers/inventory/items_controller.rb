# Items: the list and editing for inventory managers, and the item page
# (phone-first) for everyone who may use inventory (spec §3.9).
module Inventory
  class ItemsController < BaseController
    HISTORY = 50

    before_action :set_item, only: %i[show edit update destroy duplicate]

    # GET /inventory/items
    def index
      authorize Item
      @q = policy_scope(Item).ransack(params[:q])
      @q.sorts = "name asc" if @q.sorts.empty?
      @items = @q.result.includes(:team, :home_location).page(params[:page])
      @totals = Inventory::Stock.totals(@items.to_a)
    end

    # GET /inventory/items/1
    def show
      @home = visible_default_location(@item)
      @total = @item.total_stock
      @levels = @item.stock_levels.where.not(quantity: 0)
        .where(location_id: policy_scope(Location).select(:id)).includes(:location).to_a
      if @item.home_location && @levels.none? { |level| level.location_id == @item.home_location_id } && policy(@item.home_location).show?
        @levels.unshift(StockLevel.new(item: @item, location: @item.home_location, quantity: 0))
      end
      @last_counted = @item.stock_movements.counted.where(reverses_id: nil).group(:location_id).maximum(:created_at)
      @history = policy_scope(@item.stock_movements).newest_first.includes(:location, :person, :recorded_by).limit(HISTORY).to_a
      @partners = move_partners(@history)
      @undone_ids = StockMovement.where(reverses_id: @history.map(&:id)).pluck(:reverses_id).to_set
    end

    # GET /inventory/items/new
    def new
      @item = authorize Item.new(team_id: managed_teams.first&.id, home_location_id: params[:location_id])
    end

    # GET /inventory/items/1/edit
    def edit
    end

    # POST /inventory/items
    def create
      @item = authorize Item.new(item_params)

      if @item.save
        redirect_to inventory_item_path(@item), notice: "#{@item.name} was added."
      else
        render :new, status: :unprocessable_entity
      end
    end

    # PATCH/PUT /inventory/items/1
    def update
      @item.assign_attributes(item_params)
      authorize @item

      if @item.save
        redirect_to inventory_item_path(@item), notice: "#{@item.name} was saved.", status: :see_other
      else
        render :edit, status: :unprocessable_entity
      end
    end

    # POST /inventory/items/1/duplicate
    def duplicate
      copy = Inventory::ItemDuplicator.call(@item)
      redirect_to edit_inventory_item_path(copy), notice: "Duplicated. Check it, then save.", status: :see_other
    end

    # DELETE /inventory/items/1
    def destroy
      @item.destroy!
      redirect_to inventory_items_path, notice: "#{@item.name} was deleted.", status: :see_other
    end

    private

    def set_item
      @item = authorize policy_scope(Item).find(params[:id])
    end

    def item_params
      permitted = params.require(:item).permit(:team_id, :name, :description, :category, :manufacturer,
        :manufacturer_part_number, :stock_unit_id, :home_location_id, :reorder_point, :reorder_quantity, :url, :note, :active, :photo)
      if permitted[:home_location_id].present? && !policy_scope(Location).exists?(id: permitted[:home_location_id])
        permitted[:home_location_id] = nil
      end
      permitted
    end
  end
end
