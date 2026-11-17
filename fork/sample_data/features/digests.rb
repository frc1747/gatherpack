# Nothing to add: summaries come from the features that register a section
# (inventory's Running Low Notices). Turn on Summaries (feature_digests) and
# set a connected feature's notice setting to see them; with no email gateway
# they're only logged.
Hbr::SampleData.feature "feature/digests" do |s|
  s.note "no data needed (sections come from connected features; email goes through the configured gateway)"
end
