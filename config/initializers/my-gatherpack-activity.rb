# The activity page (/activity) and Home's "Also this season". Needs the
# my_gatherpack feature as well as its own flag.
Rails.application.config.to_prepare do
  next unless defined?(MyGatherpack) && MyGatherpack.respond_to?(:register_section)

  # My activity in the menu, for everyone while the page is on. Where menu
  # items take a visible check, it also needs My GatherPack itself on.
  activity_item = { label: "My activity", path: :activity_path, icon: "chart-simple" }
  activity_item[:visible] = ->(_user) { MyGatherpack::Activity.enabled? } if GatherPack::Feature::NavItem.members.include?(:visible)
  GatherPack::Features.register_section("My GatherPack", position: 5)

  GatherPack::Features.register(
    GatherPack::Feature.new(
      key: :my_gatherpack_activity,
      label: "My GatherPack: Activity",
      description: "A page of each person's own check-ins, hours, sign-ups and forms for a season, " \
        "and Home's list of activity no checklist counts. Needs My GatherPack",
      default_enabled: false,
      nav_section: "My GatherPack",
      nav_position: 10,
      nav_items: [ GatherPack::Feature::NavItem.new(**activity_item) ]
    )
  )
  MyGatherpack::Menu.singleton_class.prepend(MyGatherpack::ActivityMenuTable)
  MyGatherpack::Menu.table = MyGatherpack::Menu.table

  Settings.register(:my_gatherpack_season_start, :string, "Season Start", "05-01", "My GatherPack",
    "The day each season starts. The activity page shows one season at a time")
  Settings.input(:my_gatherpack_season_start, :month_day) if Settings.respond_to?(:input)

  # Right under the checklists' My Season section (20), as its footer.
  MyGatherpack.register_section(:activity, partial: "my_gatherpack/activity_season", column: :side, position: 20.5,
    enabled: -> { MyGatherpack::Activity.enabled? })
end
