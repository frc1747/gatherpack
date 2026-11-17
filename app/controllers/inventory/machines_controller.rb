# Machines (inventory spec §3.15): things built and run, under the name
# Inventory setup gives them, each with the units installed on it, nested
# by sub-assembly. Install a part takes a unit's code, typed or scanned from
# its label. Gone while Inventory setup turns them off.
module Inventory
  class MachinesController < BaseController
    include Inventory::UnitLookup

    before_action :require_machines
    before_action :set_machine, only: %i[show install]

    def index
      authorize :inventory, :use?
      @machines = policy_scope(Location).machine.includes(:parent).sort_by { |machine| [ machine.active? ? 0 : 1, machine.full_name ] }
      # The same units each machine's page lists.
      units = policy_scope(ItemUnit).active.where(location_id: @machines.map(&:id))
      @unit_counts = units.group(:location_id).count
      @flagged_counts = units.flagged.group(:location_id).count
    end

    def show
      units = policy_scope(ItemUnit).active.where(location: @machine).includes(:item).order(:code).to_a
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

    def require_machines
      return if Inventory.machines?

      redirect_to inventory_root_path, notice: "#{Inventory.machine_word(count: :many, capitalize: true)} are turned off"
    end

    def set_machine
      @machine = policy_scope(Location).machine.find(params[:id])
      authorize @machine, :show?
    end
  end
end
