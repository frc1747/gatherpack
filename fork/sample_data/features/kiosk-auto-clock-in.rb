# Kiosk cases: one period and two periods, already clocked in, a missed
# clock-out, clocked out earlier today, and a plain account for the kiosk
# screen. The three kiosk settings stay at their defaults; the README says
# which to change to try auto clock-in.
Hbr::SampleData.people "Kiosk Account"

Hbr::SampleData.feature "feature/kiosk-auto-clock-in" do |s|
  season = s.recall(:season)
  season_start, season_end = s.clock.season

  # Youth Program members get a second period, so they choose between two.
  youth_shifts = s.upsert!(TimeClockPeriod, { name: "Youth Program Shifts" },
    team: s.team(:youth), start_time: season_start, end_time: season_end, permission: "added_by_manager")

  # A top-level team holding only the kiosk's own login, for the "Who Can
  # Open the Kiosk" setting.
  kiosk_team = s.team!(:kiosk, "Kiosk", TeamType.find_by!(name: "Organization"), "#5e5c64")
  s.member!(s.login!(:kiosk, "kiosk", "Kiosk", "Account"), kiosk_team)

  # Punches carry this note, so each run finds and resets the same ones.
  # The first run adopts an open punch the old populate_dev.rb left, rather
  # than adding a second. They're made as the kiosk makes them.
  marker = "Sample data"
  punch = lambda do |first, start_time, end_time|
    person = s.person(first)
    record = TimeClockPunch.find_by(person: person, time_clock_period: season, note: marker) ||
      TimeClockPunch.find_by(person: person, time_clock_period: season, note: nil, end_time: nil) ||
      TimeClockPunch.new(person: person, time_clock_period: season)
    record.update!(note: marker, start_time: start_time, end_time: end_time, created_by: "kiosk")
  end
  punch.call("Ben", s.clock.hours_ago(1), nil)                     # clocked in now
  punch.call("Grace", s.clock.days_ago(1, hour: 18), nil)          # missed clock-out yesterday
  midnight = s.clock.days_from_now(0, hour: 0)
  henry_in = [ s.clock.hours_ago(3), midnight ].max                # clocked in and out today
  punch.call("Henry", henry_in, henry_in + ((s.clock.now - henry_in) / 2))

  s.report "periods #{season.name} and #{youth_shifts.name}, kiosk login kiosk@, punches for Ben (in), Grace (missed clock-out), Henry (out today)"
  s.expect("Ben and Grace have one open punch each") do
    %w[Ben Grace].all? { |first| TimeClockPunch.where(person: s.person(first), time_clock_period: season, end_time: nil).count == 1 }
  end
end
