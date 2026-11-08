require_relative "../../lib/gatherpack/smooth_pages"

Rails.application.config.to_prepare do
  GatherPack::Features.register(
    GatherPack::Feature.new(
      key: :smooth_pages,
      label: "Smooth Pages",
      description: "Keep your place after actions that return to the same page, and keep the sidebar still between pages",
      default_enabled: false
    )
  )

  # Morph applies only when an action redirects to the page's own URL. Add a page
  # with SmoothPages.refresh_on("controller#action") once it has been checked.

  GatherPack::SmoothPages.no_preview_on(
    "welcome#index",
    "calendar#index",
    "people#calendar",
    "time_clock_punches#index",
    "time_clock_periods#index",
    "time_clock_periods#show",
    "time_clock_periods#summary"
  )

  GatherPack::SidebarSlots.root_attributes(:smooth_pages) { smooth_pages_sidebar_attributes }
end
