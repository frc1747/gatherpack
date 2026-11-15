module Orders
  # Editors for the structured orders settings: approval steps, paid-with
  # choices and the price tolerance (the rest are on the settings page).
  class SettingsController < BaseController
    # GET /orders/settings
    def show
      authorize :order_settings, :show?
      @editor = Orders::SettingsEditor.new
    end

    # PATCH/PUT /orders/settings
    def update
      authorize :order_settings, :update?
      @editor = Orders::SettingsEditor.new.assign(params)

      if @editor.save
        redirect_to orders_settings_path, notice: "Orders settings were successfully updated.", status: :see_other
      else
        render :show, status: :unprocessable_entity
      end
    end
  end
end
