# Units of tracked items (inventory spec §3.15): the unit page, a page for
# each action on it, adding units to an item, and editing a unit's label
# details. Every change goes through the ItemUnit action methods, which
# check permission again and raise Inventory::Refused.
module Inventory
  class UnitsController < BaseController
    include Inventory::UnitLookup

    ACTIONS = Inventory::Config::UNIT_ACTIONS

    before_action :set_unit, only: %i[show edit update action_form] + ACTIONS.map(&:to_sym)

    # GET /inventory/units?code=A-07: finds a unit by its code, serial
    # number or name. One match opens it.
    def index
      authorize ItemUnit, :index?
      @query = params[:code].to_s.strip
      @units = @query.empty? ? policy_scope(ItemUnit).none : find_units(@query)
      redirect_to inventory_unit_path(@units.first) if @units.one?
    end

    def show
      @events = @unit.events.includes(:person, :from_location, :to_location, :from_unit, :to_unit, :via_unit, :condition_before,
        :condition_after).reverse
    end

    # GET /inventory/units/new?item_id=: units for a tracked item, as
    # received stock.
    def new
      @item = policy_scope(Item).find(params[:item_id])
      @unit = authorize ItemUnit.new(item: @item, location: @item.home_location)
    end

    def create
      @item = policy_scope(Item).find(params[:item_id])
      authorize ItemUnit.new(item: @item)
      location = policy_scope(Location).find(params[:location_id])
      units = ItemUnit.receive!(item: @item, location: location, count: params[:count], person: current_user.person,
        note: params[:note])
      redirect_to inventory_item_path(@item), notice: "#{helpers.pluralize(units.size, "unit")} added to #{location.name}",
        status: :see_other
    end

    def edit
    end

    def update
      if @unit.update(unit_params)
        redirect_to inventory_unit_path(@unit), notice: "Saved", status: :see_other
      else
        render :edit, status: :unprocessable_entity
      end
    end

    # GET /inventory/units/1/check (and the other actions): the form.
    def action_form
      @act = ACTIONS.find { |action| action == params[:act] } or raise ActionController::RoutingError, "No such action"
      authorize @unit, :"#{@act}?"
      render template: "inventory/units/#{@act}"
    end

    def install
      target = install_target
      @unit.install!(into: target, by: current_user.person, confirm: params[:confirm] == "1", note: params[:note])
      done "Installed on #{target.is_a?(ItemUnit) ? target.identifier_name : target.name}"
    rescue Inventory::ConfirmNeeded => question
      @act = "install"
      @question = question.message
      @target = target
      render :install, status: :unprocessable_entity
    end

    def take_off
      to = params[:location_id].presence && policy_scope(Location).find(params[:location_id])
      event = @unit.take_off!(by: current_user.person, to: to, note: params[:note])
      done "Taken off, now in #{event.to_location.name}"
    end

    def move
      to = policy_scope(Location).find(params[:location_id])
      @unit.move!(to: to, by: current_user.person, note: params[:note])
      done "Moved to #{to.name}"
    end

    def check
      @unit.check!(by: current_user.person, condition: params[:condition], readings: readings_params,
        note: params[:note], photo: params[:photo])
      done "Check saved"
    end

    def mark_for_repair
      @unit.mark_for_repair!(by: current_user.person, condition: params[:condition], note: params[:note])
      done "Marked #{@unit.condition_label}"
    end

    def repaired
      @unit.repaired!(by: current_user.person, condition: params[:condition], note: params[:note])
      done "Marked repaired"
    end

    def retire
      @unit.retire!(by: current_user.person, note: params[:note])
      done "Retired"
    end

    private

    def set_unit
      @unit = policy_scope(ItemUnit).includes(:item, :location, :installed_in, :unit_condition).find(params[:id])
      authorize @unit, :show? if %w[show action_form].include?(action_name)
      authorize @unit if ACTIONS.include?(action_name) || %w[edit update].include?(action_name)
    end

    # Back to the unit page, from which the action was taken.
    def done(message)
      redirect_to inventory_unit_path(@unit), notice: message, status: :see_other
    end

    # A machine (location_id, a place whose type takes installed parts) or another unit, by id (unit_id) or by its
    # code or label URL, typed or scanned (unit_code). A code more than one
    # team uses prefers this unit's team.
    def install_target
      if params[:unit_id].present?
        policy_scope(ItemUnit).find(params[:unit_id])
      elsif params[:unit_code].present?
        unit_from_code(params[:unit_code], team_id: @unit.item.team_id)
      elsif params[:location_id].present?
        policy_scope(Location).find(params[:location_id])
      elsif LocationType.installable.exists?
        raise Inventory::Refused, "Pick #{LocationType.installable_words}, or type the code of the part to put it in"
      else
        raise Inventory::Refused, "Type the code of the part to put it in"
      end
    end

    # Units whose code or serial number is the query, or failing that
    # contain it (or their name does).
    def find_units(query)
      exact = exact_units(query)
      return exact if exact.exists?

      pattern = "%#{ItemUnit.sanitize_sql_like(query.to_s.strip)}%"
      policy_scope(ItemUnit).active.includes(:item, :location).where("item_units.code ILIKE :p OR item_units.serial_number ILIKE :p OR item_units.name ILIKE :p", p: pattern)
        .order(:code).limit(50)
    end

    def exact_units(query)
      policy_scope(ItemUnit).active.includes(:item, :location)
        .where("LOWER(item_units.code) = :q OR LOWER(item_units.serial_number) = :q", q: query.to_s.strip.downcase)
    end

    def readings_params
      params.fetch(:readings, {}).permit(*@unit.item.reading_type_ids).to_h
    end

    def unit_params
      params.require(:item_unit).permit(:code, :serial_number, :name, :in_service_on, :photo)
    end
  end
end
