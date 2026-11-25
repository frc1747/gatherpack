# The "Spring Workday Helpers" sheet (from the sign-ups data) feeds "Youth
# Family Shifts" (from the commitments data), listed above a check-in source
# for Workday events and the Setup Hour source. Sign-ups count 1 each, to
# the person they're on behalf of. Paula has a Fall Fair Setup place on
# behalf of Kate (planned), which credits her family; Grace signs up for
# Work Night and checks in there (fulfilled, so confirmed), and her check-in
# adds nothing more; Sam checks in at Work Night without signing up and gets
# a shift from the check-in source. Existing sign-ups are left alone on later
# runs.
Hbr::SampleData.feature "feature/signup-credit" do |s|
  family_shifts = s.recall(:family_shifts)
  helpers = s.recall(:helpers_sheet)
  workday_type = EventType.find_by!(name: "Workday")
  setup_source = family_shifts.commitment_sources.find_by!(kind: "checkins", subject: EventType.find_by!(name: "Setup Hour"))

  # Sources in order: the sheet first, so a sign-up and a check-in by the
  # same person at the same event count once, as the sign-up.
  sheet_source = s.upsert!(CommitmentSource, { commitment: family_shifts, kind: "signups", subject: helpers }, per: 1, credits: 1, position: 1)
  workday_source = s.upsert!(CommitmentSource, { commitment: family_shifts, kind: "checkins", subject: workday_type }, per: 1, credits: 1, position: 2)
  setup_source.update!(position: 3) unless setup_source.position == 3

  greeter = helpers.signup_positions.find_by!(name: "Greeter")
  # Signs the person up through Signup.place!, unless they already have a
  # place in the slot, as the sign-ups data does.
  take = lambda do |record, person, by: person, on_behalf_of: person, **attrs|
    slot = greeter.signup_slots.find_by!(event: record)
    Signup.find_by(signup_slot: slot, person: person) ||
      Signup.place!(slot: slot, person: person, signed_up_by: by, on_behalf_of: on_behalf_of, **attrs)
  end

  work_night = Event.find_by!(name: "Work Night")
  # Paula works a place for Kate, so it credits Kate's family. Paula isn't
  # on a Northwind team, so the sheet's organizer (Chloe) puts her down.
  fair_signup = take.call(Event.find_by!(name: "Fall Fair Setup"), s.login(:parent1), by: s.person("Chloe"), on_behalf_of: s.person("Kate"),
    note: "Kate is away that weekend")
  # Signed up, then checked in, which fulfils the sign-up.
  grace_signup = take.call(work_night, s.person("Grace"))
  Checkin.find_or_create_by!(event: work_night, person: s.person("Grace"))
  # Checked in without signing up.
  Checkin.find_or_create_by!(event: work_night, person: s.person("Sam"))

  family = family_shifts.reload.progress
  at = ->(first) { family[s.person(first).id] }
  line = ->(first, source) { at.(first).lines.find { |l| l.source == source } }
  s.report "#{sheet_source.label} and #{workday_source.label} feed #{family_shifts.title}"
  s.expect("Paula's sign-up for Kate is planned") { fair_signup.reload.active? && fair_signup.on_behalf_of == s.person("Kate") }
  s.expect("Grace's Work Night sign-up was fulfilled by her check-in") { grace_signup.reload.fulfilled? }
  s.expect("the sheet credits Grace and Kate's family, confirmed and planned") do
    line.("Kate", sheet_source).then { |l| l.confirmed_credits == 1 && l.planned_credits >= 1 }
  end
  s.expect("Paula's place credits Kate, planned") do
    line.("Kate", sheet_source).records.any? do |record|
      record.label == "Greeter: Fall Fair Setup" && record.person_id == s.person("Kate").id && !record.confirmed?
    end
  end
  s.expect("Grace's check-in at Work Night counts once, as her sign-up") { line.("Grace", workday_source).records.empty? }
  s.expect("Sam has a shift from a check-in") { line.("Sam", workday_source).confirmed_credits == 1 && line.("Sam", sheet_source).records.empty? }
end
