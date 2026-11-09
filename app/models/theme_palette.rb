# A site's few base colors, worked out in Ruby into the skin's full set of
# color tokens. Registered in config/initializers/theme_palette.rb.
module ThemePalette
  FIELDS = %i[brand_color background_color surface_color text_color].freeze

  # Lives on the skin: with the skin off, the theme page stays as it is today.
  def self.active?(controller)
    GatherPack::Features.enabled?(:theme_palette) && ModernSkin.active?(controller)
  end

  # The import rewrites the one site-wide theme, so one admin's skin preview
  # isn't enough: everyone else would lose their variables and gain nothing.
  def self.on_for_everyone?
    GatherPack::Features.enabled?(:theme_palette) && GatherPack::Features.enabled?(:modern_skin)
  end

  def self.permitted_fields(controller)
    active?(controller) ? FIELDS : []
  end
end
