# The activity page (/activity) and Home's "Also this season". Needs the
# my_gatherpack feature as well as its own flag.
Rails.application.config.to_prepare do
  next unless defined?(MyGatherpack) && MyGatherpack.respond_to?(:register_section)

  GatherPack::Features.register(
    GatherPack::Feature.new(
      key: :my_gatherpack_activity,
      label: "My GatherPack: Activity",
      description: "A page of each person's own check-ins, hours, sign-ups and forms for a season, " \
        "and Home's list of activity no checklist counts. Needs My GatherPack",
      default_enabled: false
    )
  )

  Settings.register(:my_gatherpack_season_start, :string, "Season Start", "05-01", "My GatherPack",
    "The day each season starts. The activity page shows one season at a time")
  Settings.input(:my_gatherpack_season_start, :month_day) if Settings.respond_to?(:input)

  # Right under the checklists' My Season section (20), as its footer.
  MyGatherpack.register_section(:activity, partial: "my_gatherpack/activity_season", column: :side, position: 20.5,
    enabled: -> { MyGatherpack::Activity.enabled? })
end
