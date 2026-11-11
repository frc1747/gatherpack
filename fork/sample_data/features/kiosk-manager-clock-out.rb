# A manager whose team owns no time period: Ben manages Logistics Crew, and
# the season period belongs to the top team. Ben gets a login (the kiosk's
# Manager window is for managers who can sign in), and Noah, in his crew, is
# clocked in. The setting stays off; the README says how to try it.
Hbr::SampleData.feature "feature/kiosk-manager-clock-out" do |s|
  season = s.recall(:season)
  ben = s.login!(:crew_lead, "ben", "Ben", s.person("Ben").last_name)
  noah = s.person("Noah")

  marker = "Sample data"
  punch = TimeClockPunch.find_by(person: noah, time_clock_period: season, note: marker) ||
    TimeClockPunch.new(person: noah, time_clock_period: season, note: marker)
  punch.update!(start_time: s.clock.hours_ago(2), end_time: nil, created_by: "kiosk")

  s.report "Ben (ben@, manages Logistics Crew) can clock out Noah at the kiosk with \"Kiosk: Managers Clock Out the People They Manage\" on"
  s.expect("Ben manages Logistics Crew, which owns no period") do
    ben.all_managed_teams.exists?(name: "Logistics Crew") && TimeClockPeriod.where(team_id: ben.all_managed_teams.select(:id)).none?
  end
end
