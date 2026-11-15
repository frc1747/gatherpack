# Intake's columns for the person merge registry. Guarded, so this branch
# runs without feature/person-merge. to_prepare runs after every
# initializer, so the registry is loaded by then whatever the file order.
Rails.application.config.to_prepare do
  next unless defined?(GatherPack::PersonMerge)

  merge = GatherPack::PersonMerge

  merge.register :intake_entries, :person_id, label: "Registration entries"
  merge.register :intake_household_members, :person_id, label: "Registration household members"
  merge.register :intake_registrations, :created_by_id, label: "Registrations created"
end
