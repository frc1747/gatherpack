require "csv"

# The reorder list (spec §3.5): items within the manager's reach that are
# running low, grouped by where to buy them, with actions on the ticked
# rows from Inventory.extensions (Print and Download CSV are inventory's
# own).
module Inventory
  class ReorderController < BaseController
    # GET /inventory/reorder
    # GET /inventory/reorder?print=1&items[id]=quantity
    # GET /inventory/reorder.csv?items[id]=quantity
    def index
      authorize :inventory, :reorder?
      skip_policy_scope
      @reorder = reorder
      # Only an action that changes nothing runs from a GET (a link or a
      # prefetch); anything else needs the list's POST.
      return run_action(only_get: true) if params[:run].present?

      respond_to do |format|
        format.html do
          if params[:print].present?
            @rows = chosen_rows
            render :print
          else
            @teams = Team.where(id: @reorder.items.unscope(:includes).select(:team_id)).order(:name)
            @categories = @reorder.items.unscope(:includes).where.not(category: [ nil, "" ]).distinct.order(:category).pluck(:category)
            @actions = Inventory.extensions.reorder_actions(current_person)
          end
        end
        format.csv do
          send_data reorder_csv(chosen_rows), filename: "reorder-#{Date.current}.csv", type: "text/csv"
        end
      end
    end

    # POST /inventory/reorder: runs a registered action on the ticked rows.
    def run
      authorize :inventory, :reorder?
      @reorder = reorder
      run_action(only_get: false)
    end

    private

    def reorder
      Inventory::Reorder.new(current_person, team_id: params[:team_id], category: params[:category])
    end

    # Hands the ticked rows to a registered action and goes where it says.
    def run_action(only_get:)
      action = Inventory.extensions.reorder_actions(current_person).find { |entry| entry.key.to_s == params[:run].to_s }
      raise ActiveRecord::RecordNotFound if action.nil? || (only_get && !action.get?)

      rows = ticked_rows
      if rows.empty?
        redirect_to inventory_reorder_path(team_id: params[:team_id].presence, category: params[:category].presence),
          alert: "Tick the items first.", status: :see_other
      else
        redirect_to action.path.call(rows), status: :see_other
      end
    end

    # [[item, quantity]] for the ticked rows, with the quantities shown.
    def ticked_rows
      ids = Array(params[:ticked]).map(&:to_s)
      quantities = params.fetch(:quantities, {}).to_unsafe_h
      reachable(ids).map { |item| [ item, positive(quantities[item.id], item) ] }
    end

    # The rows named in items (id => quantity), or the whole list when none
    # are named.
    def chosen_rows
      named = params[:items].respond_to?(:to_unsafe_h) ? params[:items].to_unsafe_h : {}
      if named.empty?
        return @reorder.rows.sort_by { |row| [ row.vendor_name.downcase, row.item.name.downcase ] }
          .map { |row| [ row.item, row.suggested_quantity ] }
      end

      reachable(named.keys).sort_by { |item| [ item.preferred_source&.vendor_name.to_s.downcase, item.name.downcase ] }
        .map { |item| [ item, positive(named[item.id], item) ] }
    end

    # Items with these ids the person manages.
    def reachable(ids)
      access = Inventory::Access.for(current_person)
      Item.where(id: ids).includes(:item_sources).select { |item| access.manages?(item.team_id) }
    end

    def positive(value, item)
      quantity = Integer(value.to_s, 10, exception: false)
      quantity&.positive? ? quantity : item.suggested_quantity
    end

    def reorder_csv(rows)
      CSV.generate do |csv|
        csv << [ "Item", "Manufacturer", "Manufacturer part number", "Vendor", "Vendor part number", "Link", "Quantity" ]
        rows.each do |item, quantity|
          source = item.preferred_source
          csv << [ item.name, item.manufacturer, item.manufacturer_part_number, source&.vendor_name, source&.vendor_part_number,
            source&.url.presence || item.url, quantity ]
        end
      end
    end
  end
end
