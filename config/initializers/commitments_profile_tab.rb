# Adds the Commitments tab to a person's profile. Registered as its own
# feature rather than appended to :commitments so it doesn't depend on
# features.rb's to_prepare running first; its visible: check ties it to the
# commitments feature being on, and off again when checklists are on (its
# Checklists tab replaces this one).
GatherPack::Features.register(
  GatherPack::Feature.new(
    key: :commitments_profile_tab,
    label: "Commitments profile tab",
    toggleable: false,
    profile_tabs: [
      GatherPack::Feature::ProfileTab.new(
        label: "Commitments",
        path: ->(person) { person_commitments_path(person) },
        visible: lambda { |user, person|
          GatherPack::Features.enabled?(:commitments) && !GatherPack::Features.enabled?(:checklists) &&
            PersonCommitmentsPolicy.new(user, person).then { |policy| policy.show? && policy.visible_commitments.any? }
        }
      )
    ]
  )
)
