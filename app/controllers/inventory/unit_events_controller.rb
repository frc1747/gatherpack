# Undo on a unit's history (inventory spec §3.15): the recorder within
# inventory_undo_minutes, managers at any time. Writes a reversing event.
module Inventory
  class UnitEventsController < BaseController
    def undo
      event = ItemUnitEvent.where(item_unit_id: policy_scope(ItemUnit).select(:id)).find(params[:id])
      authorize event, :undo?
      event.undo!(by: current_user.person)
      redirect_to inventory_unit_path(event.item_unit), notice: "Undone", status: :see_other
    end
  end
end
