module ThemePaletteHelper
  # Empty unless the palette applies here. The theme page's preview supplies
  # unsaved colors in @theme_palette_preview.
  def theme_palette_css
    return "" unless ThemePalette.active?(controller)

    ThemePalette::Generator.new(@theme_palette_preview || Theme.instance).css
  end

  # The saved colors as preview query parameters.
  def generator_params(theme)
    ThemePalette::FIELDS.index_with { |field| theme[field] }.compact
  end
end
