# Checklists' columns that point at a person, registered where people can
# be merged (GatherPack::PersonMerge); without it there's nothing to
# register. GatherPack::PersonMerge is required by its own initializer, and
# to_prepare runs after every initializer has loaded, so file order doesn't
# matter.
#
# Stored results and pending refreshes are a cache: they move, the kept
# person's row winning where both have one, and are recomputed. Deleting the
# person merged away marks every checklist for a refresh (see
# Checklists::Invalidation::POPULATION), which covers the kept person.
Rails.application.config.to_prepare do
  next unless defined?(GatherPack::PersonMerge)

  merge = GatherPack::PersonMerge

  merge.register :checklists, :created_by_id, label: "Checklists created"
  merge.register :checklist_organizers, :person_id, unique_by: :checklist_id, model: ChecklistOrganizer,
    label: "Checklists run"
  merge.register :checklist_rules, :person_id, label: "Checklist rules",
    check: Checklists::MergeChecks.method(:rules)
  merge.register :checklist_grants, :created_by_id, label: "Checklist access given"
  merge.register :checklist_attestations, :person_id, label: "Checklist items done"
  merge.register :checklist_attestations, :attested_by_id, label: "Checklist items marked done"
  merge.register :checklist_excuses, :person_id, label: "Checklist excuses"
  merge.register :checklist_excuses, :created_by_id, label: "Checklist excuses given"
  merge.register :checklist_lists, :recorded_by_id, label: "Checklist lists recorded"
  merge.register :checklist_results, :person_id, unique_by: %i[checklist_id item_id], label: "Checklist results"
  merge.register :checklist_refreshes, :person_id, unique_by: :checklist_id, label: "Checklist refreshes"
end
