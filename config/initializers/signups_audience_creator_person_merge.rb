# Who added a sign-up sheet's audience rule moves to the kept person when
# two people are merged. Registers only when person merge is in this build.
Rails.application.config.to_prepare do
  next unless defined?(GatherPack::PersonMerge)

  GatherPack::PersonMerge.register :signup_audience_rules, :created_by_id, label: "Sign-up sheet audience rules added"
end
