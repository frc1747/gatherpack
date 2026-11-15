# The label sheet (spec §3.10): places, items and units, each with a QR
# code of its page. Unit labels are drawn by inventory/labels/_unit when
# the units screens provide it.
module Inventory
  class LabelsController < BaseController
    # GET /inventory/labels?places[]=…&items[]=…&units[]=…&inside=1
    def show
      authorize :inventory, :labels?
      places = policy_scope(Location).where(id: Array(params[:places]))
      if params[:inside].present?
        places = policy_scope(Location).where(id: places.flat_map(&:subtree_ids))
      end
      @places = places.select { |place| policy(place).labels? }
      @all_places = policy_scope(Location).index_by(&:id)
      @places.sort_by! { |place| helpers.inventory_place_name(place, @all_places).downcase }
      @items = policy_scope(Item).where(id: Array(params[:items])).includes(:item_sources).order(:name).to_a
      @units = Array(params[:units]).any? ? policy_scope(ItemUnit).where(id: Array(params[:units])).includes(:item).to_a : []
    end
  end
end
