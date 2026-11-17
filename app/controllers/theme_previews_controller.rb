# The theme page's live preview: real components in unsaved colors, shown in an
# iframe. Reads its colors from the query string and saves nothing.
class ThemePreviewsController < InternalController
  layout "theme_preview"

  before_action :check_for_admin
  before_action :check_for_palette

  helper_method :color_mode_for_page

  def show
    theme = authorize Theme.instance, :edit?
    @theme_palette_preview = ThemePalette::Picks.from_params(params, theme)
    @warnings = ThemePalette::Generator.new(@theme_palette_preview).warnings
  end

  private

  def check_for_palette
    redirect_to edit_theme_path unless ThemePalette.active?(self)
  end

  # Each iframe shows one mode, whatever this admin has chosen for themselves.
  def color_mode_for_page
    params[:mode] == "dark" ? "dark" : "light"
  end
end
