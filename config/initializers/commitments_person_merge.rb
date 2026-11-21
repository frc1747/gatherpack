# Commitments' columns for the person merge registry. Guarded, so this
# branch runs without feature/person-merge. to_prepare runs after every
# initializer, so the registry is loaded by then whatever the file order.
Rails.application.config.to_prepare do
  next unless defined?(GatherPack::PersonMerge)

  merge = GatherPack::PersonMerge

  merge.register :commitments, :created_by_id, label: "Commitments created"
  merge.register :commitment_organizers, :person_id, unique_by: :commitment_id, model: CommitmentOrganizer,
    label: "Commitment organizers"
  # Adjustments add up, so moving both people's keeps the total.
  merge.register :commitment_adjustments, :person_id, label: "Commitment adjustments"
  merge.register :commitment_adjustments, :created_by_id, label: "Commitment adjustments made"
  # A credit source's subject is a person or a login; both are covered.
  { person: "", user: " (login)" }.each do |owner, suffix|
    merge.register :commitment_sources, :subject_id, type_column: :subject_type, owner: owner,
      label: "Commitment credit sources#{suffix}"
  end
end
