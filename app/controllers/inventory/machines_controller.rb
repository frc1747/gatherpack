# Places parts get installed on (inventory spec §3.15), one page per active
# place type that takes them (Robots, Practice bases), each place with the
# units installed on it, nested by sub-assembly. Install a part takes a
# unit's code, typed or scanned from its label. /inventory/machines opens
# the first such type. A type that's retired, and its places, are gone
# from here.
module Inventory
  class MachinesController < BaseController
    include Inventory::UnitLookup

    before_action :set_machine, only: %i[show install]

    # GET /inventory/machines/type/:type_id, or /inventory/machines for the
    # first type.
    def index
      authorize :inventory, :use?
      @type = params[:type_id].present? ? LocationType.installable.find(params[:type_id]) : LocationType.installable.first
      if @type.nil? || params[:type_id].blank?
        skip_policy_scope
        return redirect_to(@type ? inventory_machine_type_path(@type) : inventory_root_path,
          notice: ("No type of place takes installed parts" unless @type))
      end

      @machines = policy_scope(Location).where(location_type: @type).includes(:parent)
        .sort_by { |machine| [ machine.active? ? 0 : 1, machine.full_name ] }
      # The same units each machine's page lists.
      units = policy_scope(ItemUnit).active.where(location_id: @machines.map(&:id))
      @unit_counts = units.group(:location_id).count
      @flagged_counts = units.flagged.group(:location_id).count
    end

    def show
      units = policy_scope(ItemUnit).active.where(location: @machine).includes(:item, :unit_condition).order(:code).to_a
      # A unit inside one the viewer can't see is listed at the top level.
      seen = units.to_set(&:id)
      @contents = units.group_by { |unit| seen.include?(unit.installed_in_id) ? unit.installed_in_id : nil }
      @flagged = units.select(&:flagged?)
      # A label scanned next opens a unit page, whose Install offers this
      # machine first.
      session[:inventory_machine_id] = @machine.id if @machine.active?
    end

    # POST /inventory/machines/1/install with code: the unit with that code
    # or serial number, or the unit whose label URL was scanned, goes on the
    # machine. A code more than one team uses prefers the machine's team. A
    # unit needing repair opens the unit's install page to confirm.
    def install
      unit = unit_from_code(params[:code], team_id: @machine.team_id)
      unit.install!(into: @machine, by: current_user.person, note: params[:note])
      redirect_to inventory_machine_path(@machine), notice: "#{unit.identifier_name} installed", status: :see_other
    rescue Inventory::ConfirmNeeded
      # The install page asks the question.
      redirect_to inventory_unit_action_form_path(unit, act: "install", location_id: @machine.id), status: :see_other
    end

    private

    def set_machine
      @machine = policy_scope(Location).machine.includes(:location_type).find(params[:id])
      authorize @machine, :show?
      return if @machine.takes_installs?

      redirect_to inventory_location_path(@machine), notice: "#{@machine.location_type.plural_name} are retired"
    end
  end
end
