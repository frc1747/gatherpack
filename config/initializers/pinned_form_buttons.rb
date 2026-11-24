Rails.application.config.to_prepare do
  GatherPack::Features.register(
    GatherPack::Feature.new(
      key: :pinned_form_buttons,
      label: "Pinned form buttons",
      description: "A long form's buttons stay at the bottom of the window, so Save is always in reach",
      default_enabled: false
    )
  )
end
