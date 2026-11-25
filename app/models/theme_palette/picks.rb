module ThemePalette
  # Colors that aren't saved yet, for the generator: the theme page's live preview.
  Picks = Struct.new(:brand_color, :background_color, :surface_color, :text_color, :custom_css, keyword_init: true) do
    # Only well-formed values get through, as the model would insist.
    def self.from_params(params, theme)
      colors = ThemePalette::FIELDS.index_with do |field|
        value = params[field]
        value.downcase if ThemePalette::Color.valid?(value)
      end
      new(**colors, custom_css: theme.custom_css)
    end
  end
end
