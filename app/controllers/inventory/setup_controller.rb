# Inventory > Setup: every inventory setting on one page for admins. With the
# settings pickers it draws the shared settings form; without them, plain
# fields saved here. GROUPS orders and groups the settings; a test fails when
# a setting registered in the "Inventory" group isn't listed.
module Inventory
  class SetupController < BaseController
    GROUPS = {
      "Who" => %i[inventory_users inventory_managers],
      "What members can do" => %i[inventory_member_kinds inventory_member_unit_actions inventory_used_needs_reason
        inventory_undo_minutes],
      "Notices" => %i[inventory_reorder_notice],
      "Defaults" => %i[inventory_default_unit],
      "Machines" => %i[inventory_machines inventory_machine_name inventory_machine_name_plural]
    }.freeze
    KEYS = GROUPS.values.flatten.freeze

    before_action { authorize :inventory_setup, action_name == "update" ? :update? : :show? }

    def show
    end

    def update
      values = params.fetch(:settings, {})
      KEYS.each { |key| Settings.set(key, values[key].to_s) if values.key?(key) }
      redirect_to inventory_setup_path, notice: "Inventory setup was saved.", status: :see_other
    end
  end
end
