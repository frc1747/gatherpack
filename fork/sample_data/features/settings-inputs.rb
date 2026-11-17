# Nothing to add: the pickers draw settings other features register. Once a
# feature calls Settings.input (tasks 292-294), its settings on the Settings
# page show pickers with the values the base and feature data already set
# (for example Sign-up Sheet Organizers and Commitment Organizers).
Hbr::SampleData.feature "feature/settings-inputs" do |s|
  s.note "no data needed (open Settings; pickers appear once features register inputs)"
end
