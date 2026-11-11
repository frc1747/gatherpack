class ThemeController < InternalController
  before_action :check_for_admin

  def show
    @theme = authorize Theme.instance
  end

  def edit
    @theme = authorize Theme.instance
  end

  def update
    @theme = authorize Theme.instance

    if params[:theme][:remove_logo] == "1"
      @theme.logo.purge
    end

    if params[:theme][:remove_pwa_icon] == "1"
      @theme.pwa_icon.purge
    end

    if @theme.update(theme_params)
      redirect_to theme_path, notice: "Theme was successfully updated.", status: :see_other
    else
      render :edit, status: :unprocessable_entity
    end
  end

  private

  def theme_params
    params.require(:theme).permit(
      :css_variables, :custom_css, :pwa_theme_color, :pwa_background_color,
      :logo, :pwa_icon
    )
  end
end
