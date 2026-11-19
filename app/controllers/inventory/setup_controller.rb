# Inventory > Setup: every inventory setting on one page for admins. With the
# settings pickers it draws the shared settings form; without them, plain
# fields saved here; Inventory Managers is drawn as rows either way
# (Inventory::ManagerRows). GROUPS orders and groups the settings; a test fails when
# a setting registered in the "Inventory" group isn't listed.
module Inventory
  class SetupController < BaseController
    GROUPS = {
      "Who" => %i[inventory_users inventory_managers],
      "What members can do" => %i[inventory_member_kinds inventory_member_unit_actions inventory_used_needs_reason
        inventory_undo_minutes],
      "Notices" => %i[inventory_reorder_notice]
    }.freeze
    # The managed lists linked under the settings, in this order.
    LISTS = %i[location_types stock_units unit_conditions reading_types].freeze
    KEYS = GROUPS.values.flatten.freeze

    before_action { authorize :inventory_setup, action_name == "update" ? :update? : :show? }

    def show
    end

    def update
      values = params.fetch(:settings, {})
      KEYS.each do |key|
        next unless values.key?(key)

        text = key == :inventory_managers ? Inventory::ManagerRows.text_from(values[key], Settings[key]) : values[key].to_s
        Settings.set(key, text)
      end
      redirect_to inventory_setup_path, notice: "Inventory setup was saved.", status: :see_other
    end
  end
end
