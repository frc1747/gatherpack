module Orders
  # Orders setup: who can ask, who approves, who buys and how purchases are
  # paid. The other orders settings stay on the settings page.
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
        redirect_to orders_settings_path, notice: "Orders setup was saved.", status: :see_other
      else
        render :show, status: :unprocessable_entity
      end
    end
  end
end
