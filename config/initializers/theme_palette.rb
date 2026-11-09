Rails.application.config.to_prepare do
  GatherPack::Features.register(
    GatherPack::Feature.new(
      key: :theme_palette,
      label: "Theme Colors",
      description: "Pick a few base colors on the theme page; the app works out the rest, in light and dark",
      default_enabled: false
    )
  )

  Theme.include(ThemePalette::Choices)
end
