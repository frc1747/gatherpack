# Machines (inventory spec §3.15): robots, practice bases and demo boards,
# each with the units installed on it, nested by sub-assembly. Install a
# part takes a unit's code, typed or scanned from its label.
module Inventory
  class MachinesController < BaseController
    before_action :set_machine, only: %i[show install]

    def index
      authorize :inventory, :use?
      @machines = policy_scope(Location).machine.includes(:parent).sort_by { |machine| [ machine.active? ? 0 : 1, machine.full_name ] }
      units = ItemUnit.active.where(location_id: @machines.map(&:id))
      @unit_counts = units.group(:location_id).count
      @flagged_counts = units.flagged.group(:location_id).count
    end

    def show
      units = policy_scope(ItemUnit).active.where(location: @machine).includes(:item).order(:code).to_a
      @contents = units.group_by(&:installed_in_id)
      @flagged = units.select(&:flagged?)
      # A label scanned next opens a unit page, whose Install offers this
      # machine first.
      session[:inventory_machine_id] = @machine.id if @machine.active?
    end

    # POST /inventory/machines/1/install with code: the unit with that code
    # (or serial number) goes on the machine. A unit needing repair opens
    # the unit's install page to confirm.
    def install
      code = params[:code].to_s.strip
      unit = code.empty? ? nil : policy_scope(ItemUnit).active
        .where("LOWER(item_units.code) = :q OR LOWER(item_units.serial_number) = :q", q: code.downcase).first
      raise Inventory::Refused, code.empty? ? "Type or scan the part's code" : "No part has the code #{code}" if unit.nil?

      unit.install!(into: @machine, by: current_user.person, note: params[:note])
      redirect_to inventory_machine_path(@machine), notice: "#{unit.identifier_name} installed", status: :see_other
    rescue Inventory::ConfirmNeeded
      # The install page asks the question.
      redirect_to inventory_unit_action_form_path(unit, act: "install", location_id: @machine.id), status: :see_other
    end

    private

    def set_machine
      @machine = policy_scope(Location).machine.find(params[:id])
      authorize @machine, :show?
    end
  end
end
