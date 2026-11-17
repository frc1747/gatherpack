# Housekeeping's columns for the person merge registry. Guarded, so this
# branch runs without feature/person-merge. to_prepare runs after every
# initializer, so the registry is loaded by then whatever the file order.
Rails.application.config.to_prepare do
  next unless defined?(GatherPack::PersonMerge)

  merge = GatherPack::PersonMerge

  # One saved view per list: the kept person's stays.
  merge.register :housekeeping_preferences, :person_id, unique_by: :list_key, model: HousekeepingPreference,
    label: "Housekeeping list views"
  merge.register :housekeeping_purges, :person_id, label: "Housekeeping purges run"
end
