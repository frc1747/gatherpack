class ColorModesController < InternalController
  before_action :check_skin_active

  # A display preference for the signed-in login, so update_columns: no
  # "users - update" hooks and no audit rows.
  def update
    skip_authorization

    mode = params[:color_mode].to_s
    return head :unprocessable_entity unless mode == "auto" || ModernSkin::COLOR_MODES.include?(mode)

    true_user.update_columns(color_mode: mode == "auto" ? nil : mode)
    head :no_content
  end

  private

  def check_skin_active
    head :not_found unless ModernSkin.active?(self)
  end
end
