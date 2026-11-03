# Nothing to add: with more than one web process, change a setting and reload
# a few times; every request shows the new value without a restart.
Hbr::SampleData.feature "feature/settings-read-through" do |s|
  s.note "no data needed (change any setting to try it)"
end
