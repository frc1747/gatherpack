Rails.application.config.to_prepare do
  GatherPack::Features.register(
    GatherPack::Feature.new(
      key: :modern_skin,
      label: "Modern Skin",
      description: "The modern look, with light and dark modes and a focused sign-in page",
      default_enabled: false
    )
  )

  GatherPack::ViewOverrides.register(
    :modern_skin,
    path: Rails.root.join("app/view_overrides/modern_skin"),
    position: 10,
    active: ->(controller) { ModernSkin.active?(controller) }
  )

  GatherPack::SidebarSlots.register(
    :skin_preview_note,
    partial: "layouts/skin_preview_note",
    position: 80,
    visible: ->(view) { ModernSkin.previewing?(view.controller) && !GatherPack::Features.enabled?(:modern_skin) }
  )

  GatherPack::SidebarSlots.register(
    :color_mode,
    partial: "layouts/color_mode",
    position: 90,
    visible: ->(view) { ModernSkin.active?(view.controller) }
  )

  ApplicationHelper.prepend(ModernSkin::CalendarColors)
end
