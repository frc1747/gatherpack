# Summaries: features register sections with GatherPack::Digests (see
# lib/gatherpack/digests.rb for the pattern), each going out in a daily email,
# the Weekly Infodump, both or neither as the feature's own setting says, or
# as each person chooses on the Email notices page. While feature_digests is
# off nothing is sent, there's no page, and features keep their own emails.
require Rails.root.join("lib/gatherpack/digests").to_s

# The Email notices page. Appended here so the routes come with this file;
# the controller turns people away while there's nothing to choose.
Rails.application.routes.append do
  resource :email_notices, only: %i[show update]
end

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

    # Each person's own choices: the kept person's choice wins, and the
    # merged-away person's move only where the kept person has none.
    GatherPack::PersonMerge.register :notice_preferences, :person_id, unique_by: :key,
      label: "Email notice choices"
  end
end
