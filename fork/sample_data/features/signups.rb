# Two sign-up sheets. "Spring Workday Helpers" offers people positions with a
# badge rule (First Aid) and an age rule (14 to 17) across four dates: one
# slot full, a couple signed up as two sign-ups, one place taken on behalf of
# another person, one sign-up fulfilled, and a date at 00:00-23:59 whose time
# isn't known yet. "Lunch Sign-ups" asks for items (one capped in a unit, one
# uncapped, one with a required question) and servers, with items brought
# and not brought at last week's lunch. Every sign-up goes through
# Signup.place!, as the app does, and each person has one place per slot (no
# extra people). Existing sign-ups are left alone on later runs.
Hbr::SampleData.feature "feature/signups" do |s|
  s.enable_feature :signups
  admin = s.login(:admin)
  root = s.team(:root)

  # Anyone with the Sheet Organizer badge (Chloe) can run sheets for any team.
  organizer_badge = s.upsert!(Badge, { name: "Sheet Organizer" },
    badge_type: BadgeType.find_or_create_by!(name: "Award"), team: nil, permission: "added_by_admin", color: "#c64600", short: "clipboard-list")
  BadgeAssignment.find_or_create_by!(badge: organizer_badge, person: s.person("Chloe"))
  s.setting :signups_organizers, "Sheet Organizer > #{root.name}"
  first_aid = Badge.find_by!(name: "First Aid")

  # The age rule needs birthdays: Grace is 16 and Kate 14 (as in the person
  # fields data, which sets them again when it is in the build).
  { "Grace" => 16, "Kate" => 14 }.each do |first, age|
    person = s.person(first)
    person.update!(birthday: s.clock.date(-100) << (12 * age)) if person.birthday.nil?
  end

  workday_type = EventType.find_or_create_by!(name: "Workday")
  event = lambda do |name, start_time, end_time, location|
    s.upsert!(Event, { name: name }, event_type: workday_type, team: root, location: location, start_time: start_time, end_time: end_time)
  end
  sheet = lambda do |title, attrs|
    s.upsert!(SignupSheet, { title: title }, { team: root, status: :open, created_by: admin, on_behalf_of_mode: :anyone }.merge(attrs))
  end
  position = lambda do |signup_sheet, name, order, attrs|
    s.upsert!(SignupPosition, { signup_sheet: signup_sheet, name: name }, { position: order }.merge(attrs))
  end
  add_event = ->(signup_sheet, record) { SignupSheetEvent.find_or_create_by!(signup_sheet: signup_sheet, event: record) }
  # Signs the person up through Signup.place!, unless they already have a
  # place in the slot. `status` sets it afterwards: fulfilled ("showed up" or
  # "brought") or no_show ("not brought").
  take = lambda do |pos, record, first, by: nil, status: nil, **attrs|
    person = s.person(first)
    slot = pos.signup_slots.find_by!(event: record)
    signup = Signup.find_by(signup_slot: slot, person: person) ||
      Signup.place!(slot: slot, person: person, signed_up_by: by ? s.person(by) : person, **attrs)
    signup.update!(status: status) if status && signup.status != status.to_s
    signup
  end

  workday = Event.find_by!(name: "Spring Workday")
  breakfast = event.call("Pancake Breakfast", s.clock.days_from_now(10, hour: 8), s.clock.days_from_now(10, hour: 11), "Community Hall")
  work_night = event.call("Work Night", s.clock.days_ago(4, hour: 18), s.clock.days_ago(4, hour: 21), "Community Hall")
  # Its time isn't known yet, so it's the whole day until an organizer sets it.
  fair_setup = event.call("Fall Fair Setup", s.clock.days_from_now(17, hour: 0), s.clock.days_from_now(17, hour: 23, min: 59), "Fairgrounds")

  helpers = sheet.call("Spring Workday Helpers",
    description: "Pick a job for each date. Some jobs need a badge or an age; the sheet says why when you can't take one.",
    contact: "Chloe, chloe@example.com")
  SignupSheetOrganizer.find_or_create_by!(signup_sheet: helpers, person: s.person("Chloe"))
  [ workday, breakfast, work_night, fair_setup ].each { |record| add_event.call(helpers, record) }

  greeter = position.call(helpers, "Greeter", 0, kind: :people, capacity: 2, description: "Welcome people at the door")
  aid = position.call(helpers, "First aid table", 1, kind: :people, capacity: 1, description: "Keep the kit stocked and help anyone who needs it")
  juniors = position.call(helpers, "Junior helper", 2, kind: :people, capacity: 4, description: "Carry, sort and run errands")
  s.upsert!(SignupPositionRule, { signup_position: aid, kind: "badge" }, badge_ids: [ first_aid.id ])
  s.upsert!(SignupPositionRule, { signup_position: juniors, kind: "age" }, min_age: 14, max_age: 17)
  helpers.sync_slots!

  # A couple, two sign-ups for one slot.
  take.call(greeter, breakfast, "Mia")
  take.call(greeter, breakfast, "Noah")
  # One place taken on behalf of another person: Ben works Ella's place.
  take.call(greeter, workday, "Ben", on_behalf_of: s.person("Ella"), note: "Covering for Ella")
  # A full slot: the one first aid place at the workday.
  take.call(aid, workday, "Ava")
  # Grace holds First Aid too, so she can take the breakfast table.
  take.call(aid, breakfast, "Grace")
  take.call(juniors, workday, "Grace")
  take.call(juniors, workday, "Kate")
  # Showed up at Work Night.
  Checkin.find_or_create_by!(event: work_night, person: s.person("Henry"))
  work_night_greeter = take.call(greeter, work_night, "Henry", status: :fulfilled)

  lunch = sheet.call("Lunch Sign-ups",
    description: "Bring something to share, or help serve.",
    contact: "Chloe, chloe@example.com")
  SignupSheetOrganizer.find_or_create_by!(signup_sheet: lunch, person: s.person("Chloe"))
  harvest = event.call("Harvest Lunch", s.clock.days_from_now(6, hour: 12), s.clock.days_from_now(6, hour: 13, min: 30), "Community Hall")
  kickoff = event.call("Kickoff Lunch", s.clock.days_ago(6, hour: 12), s.clock.days_ago(6, hour: 13, min: 30), "Community Hall")
  [ harvest, kickoff ].each { |record| add_event.call(lunch, record) }

  mains = position.call(lunch, "Main dish", 0, kind: :items, unit: "pizzas", capacity: 6, description: "Cheese or veggie")
  desserts = position.call(lunch, "Dessert", 1, kind: :items, unit: "dozen", capacity: nil, description: "As many as people bring")
  drinks = position.call(lunch, "Drinks", 2, kind: :items, unit: "cases", capacity: 3, question: "Which drinks?", question_required: true)
  servers = position.call(lunch, "Servers", 3, kind: :people, capacity: 3, description: "Plate and serve for the first half hour")
  lunch.sync_slots!

  # Last week's lunch: what came, and what didn't.
  take.call(mains, kickoff, "Frank", quantity: 3, status: :fulfilled)
  take.call(mains, kickoff, "Eve", quantity: 2, status: :no_show)
  take.call(desserts, kickoff, "Gina", quantity: 1, status: :fulfilled)
  take.call(drinks, kickoff, "Jack", quantity: 1, answer: "Lemonade", status: :fulfilled)
  take.call(servers, kickoff, "Liam", status: :fulfilled)
  # This week's: 5 of 6 pizzas, and a drinks answer.
  take.call(mains, harvest, "Frank", quantity: 3)
  take.call(mains, harvest, "Eve", quantity: 2)
  take.call(desserts, harvest, "Gina", quantity: 2)
  take.call(drinks, harvest, "Jack", quantity: 2, answer: "Lemonade and water")
  take.call(servers, harvest, "Liam")
  take.call(servers, harvest, "Mia")

  s.report "#{SignupSheet.count} sheets, #{SignupPosition.count} positions, #{Signup.count} sign-ups"
  s.expect("the first aid slot at the workday is full") { SignupSlot.find_by!(signup_position: aid, event: workday).full? }
  s.expect("Grace and Kate are both signed up as junior helpers") { SignupSlot.find_by!(signup_position: juniors, event: workday).signups.counted.count == 2 }
  s.expect("one sign-up is on behalf of someone else") { Signup.where(signup_slot: greeter.signup_slots).where.not("on_behalf_of_id = person_id").exists? }
  s.expect("a people sign-up is fulfilled") { work_night_greeter.reload.fulfilled? }
  s.expect("items were brought and not brought") { mains.signups.fulfilled.exists? && mains.signups.no_show.exists? }
  s.expect("the lunch has pizzas to spare") { SignupSlot.find_by!(signup_position: mains, event: harvest).remaining == 1 }
end
