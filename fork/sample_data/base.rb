# Base layer: the Northwind Community. Teams, people, the admin and manager
# logins, badges, events, the season time clock period and scan cards.
# Feature layers build on these records. Names match the old
# ~/dev/gatherpack-dev-data/populate_dev.rb, so databases it filled update
# in place.
module Hbr
  module SampleData
    module Northwind
      FIRST = %w[Ava Ben Chloe Dan Ella Finn Grace Henry Isla Jack Kate Liam Mia Noah Olive Paul Quinn Ruby Sam Tara Uma Vic Wes Xena Yara Zane Carol Eve Frank Gina].freeze
      LAST = %w[Smith Smithers Smithson Jones Brown Garcia Miller Davis Lopez Wilson Moore Taylor Clark Lewis Walker Young].freeze
      MEMBERS = FIRST.each_with_index.map { |first, i| [ first, LAST[i % LAST.size] ] }.freeze
      LOGINS = [ [ "Adam", "Admin" ], [ "Mara", "Manager" ] ].freeze
      # Scan cards go to these people in last-name order: 10000001 and up.
      CARD_HOLDERS = (MEMBERS + LOGINS).sort_by { |first, last| [ last, first ] }.freeze
    end
  end
end

Hbr::SampleData.people((Hbr::SampleData::Northwind::MEMBERS + Hbr::SampleData::Northwind::LOGINS).map { |name| name.join(" ") })

Hbr::SampleData.base do |s|
  northwind = Hbr::SampleData::Northwind

  org_type = TeamType.find_or_create_by!(name: "Organization") { |t| t.icon = "building" }
  division_type = TeamType.find_or_create_by!(name: "Division") { |t| t.icon = "sitemap" }
  crew_type = TeamType.find_or_create_by!(name: "Crew") { |t| t.icon = "people-group" }

  root = s.team!(:root, "Northwind Community", org_type, "#1c71d8")
  operations = s.team!(:operations, "Operations", division_type, "#e66100", root)
  programs = s.team!(:programs, "Programs", division_type, "#26a269", root)
  facilities = s.team!(:facilities, "Facilities Crew", crew_type, "#c64600", operations)
  logistics = s.team!(:logistics, "Logistics Crew", crew_type, "#986a44", operations)
  youth = s.team!(:youth, "Youth Program", crew_type, "#2ec27e", programs)
  adult = s.team!(:adult, "Adult Education", crew_type, "#33d17a", programs)

  admin = s.login!(:admin, "admin", "Adam", "Admin", admin: true)
  manager = s.login!(:manager, "manager", "Mara", "Manager")
  s.member!(admin, root, manager: true)
  s.member!(manager, programs, manager: true)

  crews = [ facilities, logistics, youth, adult ]
  northwind::MEMBERS.each_with_index do |(first, last), i|
    person = s.person!(first, last)
    s.member!(person, crews[i % crews.size])
    # A few people belong to two crews.
    s.member!(person, crews[(i + 1) % crews.size]) if (i % 7).zero?
  end
  # Crew leads
  { "Ava" => facilities, "Ben" => logistics, "Chloe" => youth, "Dan" => adult }.each do |first, team|
    s.member!(s.person(first), team, manager: true)
  end

  certification = BadgeType.find_or_create_by!(name: "Certification")
  award = BadgeType.find_or_create_by!(name: "Award")
  badge = lambda do |name, type, team, permission, color, short|
    s.upsert!(Badge, { name: name }, badge_type: type, team: team, permission: permission, color: color, short: short)
  end
  first_aid = badge.call("First Aid", certification, root, "added_by_manager", "#e01b24", "kit-medical")
  badge.call("Forklift Operator", certification, facilities, "added_by_manager", "#f6d32d", "truck")
  badge.call("Youth Protection", certification, programs, "added_by_manager", "#3584e4", "shield")
  badge.call("Volunteer of the Month", award, nil, "added_by_admin", "#9141ac", "star")
  %w[Ava Ben Grace].each { |first| BadgeAssignment.find_or_create_by!(badge: first_aid, person: s.person(first)) }

  workday_type = EventType.find_or_create_by!(name: "Workday")
  CheckinField.find_or_create_by!(event_type: workday_type, name: "T-shirt size") { |f| f.permission = "added_by_participant" }
  CheckinField.find_or_create_by!(event_type: workday_type, name: "Station") { |f| f.permission = "added_by_manager" }

  workday = s.upsert!(Event, { name: "Spring Workday" },
    event_type: workday_type, team: root, location: "Community Hall", checkin_limit: 25,
    start_time: s.clock.days_from_now(3, hour: 9), end_time: s.clock.days_from_now(3, hour: 15))
  %w[Ava Ben].each { |first| Checkin.find_or_create_by!(event: workday, person: s.person(first)) }

  s.upsert!(Event, { name: "Youth Campout" },
    event_type: workday_type, team: youth, location: "Pine Ridge", locked: true,
    start_time: s.clock.next_weekday(:saturday, hour: 16), end_time: s.clock.next_weekday(:saturday, hour: 16) + 19.hours)

  season_start, season_end = s.clock.season
  # Named for its years ("2026-27 Season"), as the old script named it.
  s.remember :season, s.upsert!(TimeClockPeriod, { name: "#{season_start.year}-#{format("%02d", season_end.year % 100)} Season" }, team: root, start_time: season_start, end_time: season_end, permission: "added_by_admin")

  northwind::CARD_HOLDERS.each_with_index do |(first, last), i|
    token = Token.find_or_initialize_by(value: format("1000%04d", i + 1))
    token.update!(tokenable: Person.find_by!(first_name: first, last_name: last)) unless token.persisted?
  end

  s.report "#{Team.count} teams, #{Person.count} people, #{Badge.count} badges, #{Event.count} events, #{Token.count} cards"
  s.expect("both base logins exist") { User.where(email: %w[admin@example.com manager@example.com]).count == 2 }
end
