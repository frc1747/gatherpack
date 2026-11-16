# Inventory > Setup: who can use inventory, who manages it and the running
# low notices, on one page for admins. With the settings pickers it draws
# the shared settings form; without them, plain fields saved here.
module Inventory
  class SetupController < BaseController
    KEYS = %i[inventory_users inventory_managers inventory_reorder_notice].freeze

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
