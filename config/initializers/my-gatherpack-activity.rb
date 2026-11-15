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
    "The month and day each season starts, as MM-DD. The activity page shows one season at a time")

  # Just after the checklists' My Season section, as its footer.
  MyGatherpack.register_section(:activity, partial: "my_gatherpack/activity_season", column: :side, position: 21,
    enabled: -> { MyGatherpack::Activity.enabled? })
end
