Rails.application.config.to_prepare do
  GatherPack::Features.register(
    GatherPack::Feature.new(
      key: :screen_standard,
      label: "Standard buttons on built-in screens",
      description: "Cancel on built-in forms is grey instead of yellow, so it no longer looks like Edit; event and person pages show Edit first and put their other actions in More",
      default_enabled: false
    )
  )
end
