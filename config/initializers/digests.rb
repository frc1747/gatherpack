# Summaries: features register sections with GatherPack::Digests (see
# lib/gatherpack/digests.rb for the pattern), each going out in a daily email,
# the Weekly Infodump, both or neither as the feature's own setting says.
# While feature_digests is off nothing is sent and features keep their own
# emails.
require Rails.root.join("lib/gatherpack/digests").to_s

Rails.application.config.to_prepare do
  GatherPack::Features.register(
    GatherPack::Feature.new(
      key: :digests,
      label: "Summaries",
      description: "Combine features' summaries into one daily email per person or the Weekly Infodump",
      default_enabled: false
    )
  )

  # Which days a person's daily summary went out: bookkeeping only, removed
  # with the person, so a merge leaves it behind rather than moving it.
  if defined?(GatherPack::PersonMerge)
    GatherPack::PersonMerge.exempt :digest_deliveries, :person_id,
      reason: "Daily summary send log; rows go with the person (on delete cascade)"
  end
end
