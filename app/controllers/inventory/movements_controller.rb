require "csv"

# Changes: the Used, Moved, Counted, Received, Added and Removed forms
# (phone-first), Undo, and the Changes list for inventory managers (spec
# §3.3, §3.9). Every change goes through StockMovement.record! or #undo!.
module Inventory
  class MovementsController < BaseController
    PER_PAGE = 100

    before_action :set_form, only: %i[new create]

    # GET /inventory/changes
    def index
      authorize :inventory, :changes?
      within_reach = in_reach(policy_scope(StockMovement))
      @movements = filtered(within_reach).newest_first.includes(:item, :location, :person, :recorded_by, :reverses)
      @places = policy_scope(Location).ordered
      @people = Person.where(id: within_reach.select(:person_id)).order(:display_name)

      respond_to do |format|
        format.html do
          @movements = @movements.page(params[:page]).per(params[:print].present? ? 1000 : PER_PAGE)
          @partners = move_partners(@movements)
        end
        format.csv do
          send_data changes_csv(@movements.limit(10_000)), filename: "changes-#{Date.current}.csv", type: "text/csv"
        end
      end
    end

    # GET /inventory/changes/new?kind=used&item_id=…&location_id=…
    def new
    end

    # POST /inventory/changes
    def create
      @quantity = params[:quantity]
      @reason = params[:reason]
      @note = params[:note]
      movement = StockMovement.record!(kind: @kind, item: @item, person: current_person, location: @location,
        to_location: @to_location, quantity: @quantity, reason: @reason, note: @note)
      offer_undo(movement)
      redirect_to return_path(inventory_item_path(@item)), status: :see_other
    rescue Inventory::Refused => error
      @error = error.message
      render :new, status: :unprocessable_entity
    end

    # POST /inventory/changes/1/undo
    def undo
      movement = authorize policy_scope(StockMovement).find(params[:id])
      movement.undo!(by: current_person)
      redirect_to return_path(inventory_item_path(movement.item)), notice: "Undone: #{helpers.inventory_change_text(movement)}.",
        status: :see_other
    end

    private

    # The item, kind and places of the form, and the check that this person
    # may record that kind of change for the item somewhere.
    def set_form
      @item = policy_scope(Item).find(params[:item_id])
      @kind = params[:kind].to_s
      raise ActiveRecord::RecordNotFound unless StockMovement::KINDS.include?(@kind)

      places = policy_scope(Location).active.storage
      @stocked = places.where(id: @item.stock_levels.where.not(quantity: 0).select(:location_id)).ordered.to_a
      @choices = places.ordered.to_a
      @location = find_place(params[:location_id]) || (visible_default_location(@item) if @kind.in?(%w[used received added])) ||
        (@stocked.first if @kind.in?(%w[used moved counted removed]) && @stocked.one?)
      @to_location = find_place(params[:to_location_id])
      @places = policy_scope(Location).index_by(&:id)
      @cancel_path = return_path(inventory_item_path(@item))

      authorize StockMovement.new(kind: @kind, item: @item, location: @location || @stocked.first || @choices.first)
    end

    # Changes lists movements within the manager's reach (spec §3.9): items
    # of the teams whose inventory they manage, not everything they can see.
    def in_reach(scope)
      access.admin? ? scope : scope.where(item_id: Item.where(team_id: access.managed_team_ids.to_a).select(:id))
    end

    def find_place(id)
      id.present? ? policy_scope(Location).find_by(id: id) : nil
    end

    def filtered(scope)
      scope = scope.where(kind: params[:kind]) if StockMovement::KINDS.include?(params[:kind])
      scope = scope.where(location_id: params[:location_id]) if params[:location_id].present?
      scope = scope.where(person_id: params[:person_id]) if params[:person_id].present?
      from = parse_date(params[:from])
      to = parse_date(params[:to])
      scope = scope.where(created_at: from.beginning_of_day..) if from
      scope = scope.where(created_at: ..to.end_of_day) if to
      scope
    end

    def parse_date(value)
      Date.iso8601(value.to_s)
    rescue Date::Error
      nil
    end

    def changes_csv(movements)
      CSV.generate do |csv|
        csv << [ "When", "Kind", "Item", "Place", "Quantity", "Counted", "Who", "Entered by", "Reason", "Note", "Undo of" ]
        movements.each do |movement|
          csv << [ movement.created_at.iso8601, helpers.inventory_kind_label(movement.kind), movement.item.name,
            movement.location.full_name, movement.quantity, movement.counted_quantity, movement.person&.identifier_name,
            movement.recorded_by&.identifier_name, movement.reason, movement.note, movement.reverses&.neat_id ]
        end
      end
    end
  end
end
