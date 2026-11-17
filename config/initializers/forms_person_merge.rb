# Forms' columns that point at a person, registered where people can be
# merged (GatherPack::PersonMerge); without it there's nothing to register.
# GatherPack::PersonMerge is required by its own initializer, and to_prepare
# runs after every initializer has loaded, so file order doesn't matter.
Rails.application.config.to_prepare do
  next unless defined?(GatherPack::PersonMerge)

  merge = GatherPack::PersonMerge

  merge.register :forms, :created_by_id, label: "Forms created"
  merge.register :form_responses, :subject_id, unique_by: :form_id, model: FormResponse, label: "Form responses",
    on_conflict: FormResponseMerge.method(:resolve), check: FormResponseMerge.method(:both_answered)
  merge.register :form_submissions, :created_by_id, label: "Form answers started"
  merge.register :form_submissions, :submitted_by_id, label: "Form answers submitted"
  merge.register :form_signatures, :signer_id, label: "Signatures"
  merge.register :form_signatures, :revoked_by_id, label: "Signatures revoked"
  merge.register :form_audience_rules, :person_id, unique_by: %i[form_id effect target_type team_id badge_id],
    model: FormAudienceRule, label: "Form audiences"
  merge.register :form_reminders, :sent_by_id, label: "Form reminders sent"
end
