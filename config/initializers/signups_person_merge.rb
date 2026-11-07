# Sign-ups' columns for the person merge registry. Guarded, so this branch
# runs without feature/person-merge. to_prepare runs after every
# initializer, so the registry is loaded by then whatever the file order.
Rails.application.config.to_prepare do
  next unless defined?(GatherPack::PersonMerge)

  merge = GatherPack::PersonMerge

  # Both people can end up in one slot, which counts twice. Nothing is
  # cancelled; the preview warns so someone can look afterwards.
  both_in_a_slot = ->(from, to) {
    shared = Signup.live.where(person_id: from).where(signup_slot_id: Signup.live.where(person_id: to).select(:signup_slot_id)).distinct.count(:signup_slot_id)
    next if shared.zero?

    "#{shared} #{"slot".pluralize(shared)} would hold both people. Both sign-ups stay; check them after the merge."
  }

  merge.register :signups, :person_id, label: "Sign-ups", check: both_in_a_slot
  merge.register :signups, :on_behalf_of_id, label: "Sign-ups made for them"
  merge.register :signups, :signed_up_by_id, label: "Sign-ups made by them"
  merge.register :signup_sheets, :created_by_id, label: "Sign-up sheets created"
  merge.register :signup_sheet_organizers, :person_id, unique_by: :signup_sheet_id, model: SignupSheetOrganizer,
    label: "Sign-up sheet organizers"
  merge.register :signup_audience_rules, :person_id, unique_by: %i[signup_sheet_id effect target_type team_id badge_id],
    model: SignupAudienceRule, label: "Sign-up sheet audience rules"
end
