# "Use these as my starting colors": turns old CSS variables into color picks.
class ThemePaletteImportsController < InternalController
  before_action :check_for_admin
  before_action :check_for_palette

  def create
    result = authorize(Theme.instance, :update?).use_css_variables_as_colors!
    redirect_to edit_theme_path, notice: result.summary, status: :see_other
  end

  private

  def check_for_palette
    redirect_to edit_theme_path unless ThemePalette.on_for_everyone?
  end
end
