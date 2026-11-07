require "test_helper"
require_relative "../support/checklists_world"

class HousekeepingTest < ActiveSupport::TestCase
  include ChecklistsWorld
  include SettingsTestHelper

  setup do
    build_checklists_world
    @trip = create_world_checklist("Trip 2026", starts_on: Date.new(2025, 9, 1), ends_on: Date.new(2026, 6, 30))
    @old_event = Event.create!(name: "Kickoff 2025", event_type: event_types(:one), team: @club,
      start_time: Time.zone.local(2025, 9, 1, 18), end_time: Time.zone.local(2025, 9, 1, 20))
    @new_event = Event.create!(name: "Kickoff 2026", event_type: event_types(:one), team: @club,
      start_time: 2.days.ago, end_time: 2.days.ago + 2.hours)
  end

  def with_housekeeping(**settings, &block)
    with_settings(feature_checklists: "true", feature_housekeeping: "true", feature_events: "true", **settings, &block)
  end

  def user(name)
    person(name).user
  end

  # Registry

  test "the built-in types and purges are registered, and none is offered while the feature is off" do
    assert_equal %w[announcements checklists events], (Housekeeping.types.keys & %w[checklists events announcements]).sort
    assert_includes Housekeeping.purges.keys, "denied_applications"
    assert_includes Housekeeping.purges.keys, "field_answers"
    assert_nil Housekeeping.type(:events)
    assert_nil Housekeeping.purge(:denied_applications)

    with_housekeeping do
      assert_equal Event, Housekeeping.type(:events).model
      assert_equal Event, Housekeeping.type_for(Event).model
      assert Housekeeping.purge(:denied_applications)
    end
  end

  test "a type's own switch hides it" do
    with_housekeeping(feature_checklists: "false") do
      assert_nil Housekeeping.type(:checklists)
      assert Housekeeping.type(:events)
    end
  end

  test "ended_by finds what ended on or before a date, by a date or a time column" do
    with_housekeeping do
      events = Housekeeping.type(:events)
      ours = Event.where(id: [ @old_event.id, @new_event.id ])
      assert_equal [ @old_event ], events.ended_by(ours, Date.new(2025, 9, 1)).to_a
      assert_empty events.ended_by(ours, Date.new(2025, 8, 31))

      checklists = Housekeeping.type(:checklists)
      assert_includes checklists.ended_by(Checklist.all, Date.new(2026, 6, 30)), @trip
      assert_not_includes checklists.ended_by(Checklist.all, Date.new(2026, 6, 29)), @trip
    end
  end

  # Preview, archive and restore

  test "archiving skips a checklist another one requires, and says so" do
    with_housekeeping do
      travel_prep = create_world_checklist("Gear check")
      add_item(travel_prep, :checklist, "Trip done", { checklist_id: @trip.id })
      plain = create_world_checklist("Plain 2025", starts_on: Date.new(2024, 9, 1), ends_on: Date.new(2025, 6, 30))

      preview = Housekeeping::Preview.new(Housekeeping.type(:checklists), :archive, [ @trip, plain ], user(:club_manager))
      assert_equal [ plain ], preview.ready
      assert_equal [ @trip ], preview.skipped.map(&:record)
      assert_equal "still used by Gear check", preview.skipped.first.reason
      assert_equal "1 checklist will be archived. 1 skipped.", preview.sentence

      preview.apply!
      assert plain.reload.archived?
      assert @trip.reload.active?
    end
  end

  test "a checklist only an archived one requires can be archived" do
    with_housekeeping do
      old = create_world_checklist("Old prep", status: :archived)
      add_item(old, :checklist, "Trip done", { checklist_id: @trip.id })

      preview = Housekeeping::Preview.new(Housekeeping.type(:checklists), :archive, [ @trip ], user(:admin))
      assert_equal [ @trip ], preview.ready
    end
  end

  test "archiving skips what's already archived and what the person can't change" do
    with_housekeeping do
      @old_event.update!(archived_at: 1.day.ago)
      outside = Event.create!(name: "Elsewhere", event_type: event_types(:one), team: @other_org, start_time: 1.year.ago, end_time: 1.year.ago + 1.hour)

      preview = Housekeeping::Preview.new(Housekeeping.type(:events), :archive, [ @old_event, @new_event, outside ], user(:club_manager))
      assert_equal [ @new_event ], preview.ready
      assert_equal({ @old_event => "already archived", outside => "you can't change it" }, preview.skipped.to_h { |skip| [ skip.record, skip.reason ] })
    end
  end

  test "restore brings back what was archived, with archived_at or a status" do
    with_housekeeping do
      events = Housekeeping.type(:events)
      events.archive!(@old_event)
      assert events.archived?(@old_event.reload)
      assert_equal [ @new_event ], events.unarchived(Event.where(id: [ @old_event.id, @new_event.id ])).to_a

      preview = Housekeeping::Preview.new(events, :restore, [ @old_event, @new_event ], user(:admin))
      assert_equal [ @old_event ], preview.ready
      assert_equal "not archived", preview.skipped.first.reason
      preview.apply!
      assert_nil @old_event.reload.archived_at

      @trip.update!(status: :archived)
      Housekeeping::Preview.new(Housekeeping.type(:checklists), :restore, [ @trip ], user(:club_manager)).apply!
      assert @trip.reload.active?
    end
  end

  # Nightly job

  test "the nightly job archives nothing by default" do
    with_housekeeping do
      HousekeepingNightlyJob.perform_now
      assert_nil @old_event.reload.archived_at
      assert_nil Housekeeping.type(:events).auto_archive_days
    end
  end

  test "the nightly job archives what ended more than the set days ago, and nothing while the feature is off" do
    with_settings(feature_events: "true", housekeeping_archive_events_after_days: "30") do
      HousekeepingNightlyJob.perform_now
      assert_nil @old_event.reload.archived_at
    end

    with_housekeeping(housekeeping_archive_events_after_days: "30") do
      HousekeepingNightlyJob.perform_now
      assert @old_event.reload.archived_at
      assert_nil @new_event.reload.archived_at
    end
  end

  test "checklists archive under the housekeeping setting, reading the old one while it's blank" do
    with_housekeeping(checklists_archive_after: "2026-07-01") do
      checklists = Housekeeping.type(:checklists)
      assert Settings.get(:housekeeping_archive_checklists_after_days)
      assert_equal Date.new(2026, 6, 30), checklists.auto_archive_cutoff(Date.new(2026, 11, 1))
      assert checklists.due?(@trip, Date.new(2026, 11, 1))

      with_settings(housekeeping_archive_checklists_after_days: "200") do
        assert_not checklists.due?(@trip, Date.new(2026, 11, 1)), "the new setting wins"
        HousekeepingNightlyJob.perform_now
        assert @trip.reload.active?
      end

      Housekeeping.run(Date.new(2026, 11, 1))
      assert @trip.reload.archived?
    end
  end

  test "an ended checklist another requires stays active and shows the problem" do
    with_housekeeping(housekeeping_archive_checklists_after_days: "0") do
      gear = create_world_checklist("Gear check")
      add_item(gear, :checklist, "Trip done", { checklist_id: @trip.id })

      Housekeeping.run
      assert @trip.reload.active?
      assert_includes @trip.problems.join, "Gear check still requires it"
    end
  end

  test "an event with no end time ended when it started" do
    with_housekeeping(housekeeping_archive_events_after_days: "30") do
      open_ended = Event.create!(name: "Old social", event_type: event_types(:one), team: @club, start_time: Time.zone.local(2023, 5, 1, 18))
      events = Housekeeping.type(:events)

      assert_equal Date.new(2023, 5, 1), events.ended_on(open_ended)
      assert_includes events.ended_by(Event.all, Date.new(2023, 5, 1)), open_ended
      assert_not_includes events.ended_by(Event.all, Date.new(2023, 4, 30)), open_ended
      assert_equal Date.new(2025, 9, 1), events.ended_on(@old_event), "an end time still counts first"

      Housekeeping.run
      assert open_ended.reload.archived_at
    end
  end

  # Activity

  test "people without activity since a date leave out the recently active and the recently added" do
    with_housekeeping do
      members = Person.where(id: @members.memberships.select(:person_id))
      members.update_all(created_at: 3.years.ago)
      old_event = Event.create!(name: "Old", event_type: event_types(:one), team: @club, start_time: 2.years.ago, end_time: 2.years.ago + 1.hour)
      recent = Event.create!(name: "Recent", event_type: event_types(:one), team: @club, start_time: 1.day.ago, end_time: 1.day.ago + 1.hour)
      Checkin.create!(event: recent, person: person(:member))
      Checkin.create!(event: old_event, person: person(:member2), created_at: 2.years.ago)
      TimeClockPunch.new(person: person(:rookie), start_time: 1.day.ago, end_time: 1.day.ago + 1.hour).save!(validate: false)
      newcomer = create_world_person("Newcomer", @members)

      idle = Housekeeping.people_without_activity_since(1.month.ago, scope: members)
      assert_includes idle, person(:member2)
      assert_includes idle, person(:kid)
      assert_not_includes idle, person(:member)
      assert_not_includes idle, person(:rookie)
      assert_not_includes idle, newcomer
    end
  end

  # Copy

  test "copy selected shifts each copy's dates and offers the year-named replacements once" do
    with_housekeeping do
      add_item(@trip, :badge, "Safety", { badge_ids: [ @safety.id ] })
      safety_next = create_world_badge("Safety 2027")
      second = create_world_checklist("Camp 2026", starts_on: Date.new(2026, 7, 1), ends_on: Date.new(2026, 8, 1))
      add_item(second, :badge, "Safety", { badge_ids: [ @safety.id ] })

      copy = Housekeeping::BulkCopy.new(Housekeeping.type(:checklists), [ @trip, second ], user(:admin), shift_months: 12)
      assert_equal "2 checklists will be copied as drafts, dates moved on 1 year.", copy.sentence
      trip_changes = copy.date_changes.to_h[@trip].to_h { |change| [ change.key, change.proposed ] }
      assert_equal Date.new(2026, 9, 1), trip_changes["checklist.starts_on"]
      assert_equal Date.new(2027, 6, 30), trip_changes["checklist.ends_on"]
      assert_equal [ @safety ], copy.replacements.map(&:record)
      assert_equal safety_next, copy.replacements.first.proposed

      result = copy.apply!(replace: { "Badge:#{@safety.id}" => safety_next.id })
      assert_empty result[:failed]
      trip_copy = Checklist.find_by!(title: "Trip 2027")
      camp_copy = Checklist.find_by!(title: "Camp 2027")
      assert [ trip_copy, camp_copy ].all?(&:draft?)
      assert_equal Date.new(2027, 6, 30), trip_copy.ends_on
      assert_equal Date.new(2027, 8, 1), camp_copy.ends_on
      assert_equal [ safety_next.id ], trip_copy.checklist_items.first.config["badge_ids"]
      assert_equal [ safety_next.id ], camp_copy.checklist_items.first.config["badge_ids"]
    end
  end

  test "checklists copied together stay linked to each other's copies" do
    with_housekeeping do
      eligibility = create_world_checklist("Eligibility (last year)", starts_on: Date.new(2025, 9, 1), ends_on: Date.new(2026, 6, 30))
      packing = create_world_checklist("Packing (last year)", starts_on: Date.new(2025, 9, 1), ends_on: Date.new(2026, 6, 30))
      add_item(packing, :checklist, "Eligible", { checklist_id: eligibility.id })

      # Selected with the one that requires the other first.
      copy = Housekeeping::BulkCopy.new(Housekeeping.type(:checklists), [ packing, eligibility ], user(:admin))
      assert_equal [ [ packing, [ eligibility ] ] ], copy.links
      assert_not_includes copy.replacements.map(&:record), eligibility

      result = copy.apply!
      assert_empty result[:failed]
      new_eligibility = Checklist.find_by!(title: "Eligibility (last year) (copy)")
      new_packing = Checklist.find_by!(title: "Packing (last year) (copy)")
      assert_equal new_eligibility.id, new_packing.checklist_items.first.config["checklist_id"]

      archive = Housekeeping::Preview.new(Housekeeping.type(:checklists), :archive, [ eligibility, packing ], user(:admin))
      assert_equal [ packing ], archive.ready, "last year's packing list no longer holds up last year's eligibility through the copy"
      assert_equal "still used by Packing (last year)", archive.skipped.first.reason
    end
  end

  test "a bulk copy says which rules naming something deleted it leaves out" do
    with_housekeeping do
      gone = Person.create!(first_name: "Gone", last_name: "World")
      Membership.create!(person: gone, team: @members)
      add_rule(@trip, :exclude, :person, person_id: gone.id)
      gone.destroy!

      copy = Housekeeping::BulkCopy.new(Housekeeping.type(:checklists), [ @trip ], user(:admin))
      assert_equal [ @trip ], copy.left_out.map(&:first)
      assert_equal 1, copy.left_out.first.last.size
    end
  end

  test "copy skips what the person may not copy, and names without a year get (copy)" do
    with_housekeeping do
      plain = create_world_checklist("Roster")
      copy = Housekeeping::BulkCopy.new(Housekeeping.type(:checklists), [ plain ], user(:outsider))
      assert_empty copy.ready
      assert_equal "you can't copy it", copy.skipped.first.reason

      Housekeeping::BulkCopy.new(Housekeeping.type(:checklists), [ plain ], user(:club_manager)).apply!
      assert Checklist.exists?(title: "Roster (copy)", status: :draft)
    end
  end

  test "the shared date shift moves dates and the years in names" do
    shifter = Class.new { include Housekeeping::DateShift }.new
    shifter.instance_variable_set(:@shift_months, 12)
    assert_equal Date.new(2027, 2, 28), shifter.shift(Date.new(2026, 2, 28))
    assert_equal "Class of 2031, 2027 season", shifter.shift_name("Class of 2030, 2026 season")
    assert_equal "Trip 2027", shifter.copy_title("Trip 2026")
    assert_equal "Roster (copy)", shifter.copy_title("Roster")
  end

  # Purges

  test "the denied applications purge is set to 12 months and removes only old denied ones, with their history" do
    with_housekeeping do
      purge = Housekeeping.purge(:denied_applications)
      assert_equal 12, purge.months

      old = MembershipApplication.create!(person: person(:member), team: @joiners)
      old.update!(status: :denied, reviewed_at: 13.months.ago)
      recent = MembershipApplication.create!(person: person(:member2), team: @joiners)
      recent.update!(status: :denied, reviewed_at: 1.month.ago)
      pending = MembershipApplication.find_by!(person: person(:applicant))
      assert AuditLog.where(item_type: "MembershipApplication", item_id: old.id).exists?

      assert_equal [ old ], purge.records(purge.default_cutoff).to_a
      log = purge.run!(cutoff: purge.default_cutoff, by: person(:admin))

      assert_not MembershipApplication.exists?(old.id)
      assert MembershipApplication.exists?(recent.id)
      assert MembershipApplication.exists?(pending.id)
      assert_not AuditLog.where(item_type: "MembershipApplication", item_id: old.id).exists?
      assert_equal [ "denied_applications", 1, person(:admin) ], [ log.key, log.count, log.person ]
      assert AuditLog.where(item_type: "HousekeepingPurge", item_id: log.id, event: "create").exists?
    end
  end

  test "a blank age turns a purge off" do
    with_housekeeping(housekeeping_purge_denied_applications_months: "") do
      purge = Housekeeping.purge(:denied_applications)
      assert_not purge.enabled?
      assert_nil purge.default_cutoff
      assert_raises(ArgumentError) { purge.run!(cutoff: Date.current, by: person(:admin)) }
    end
  end

  test "the field answers purge clears the named fields of people with no activity, and nothing else" do
    with_housekeeping(feature_person_fields: "true", housekeeping_purge_fields: "Medical\n") do
      group = PersonFieldGroup.create!(name: "Medical")
      allergies = PersonField.create!(name: "Allergies", key: "allergies", person_field_group: group)
      shirt = PersonField.create!(name: "Shirt", key: "shirt")
      [ person(:member), person(:member2) ].each do |who|
        who.update_columns(created_at: 4.years.ago)
        PersonFieldValue.create!(person: who, person_field: allergies, value: "Peanuts")
        PersonFieldValue.create!(person: who, person_field: shirt, value: "M")
      end
      event = Event.create!(name: "Recent", event_type: event_types(:one), team: @club, start_time: 1.day.ago, end_time: 1.day.ago + 1.hour)
      Checkin.create!(event: event, person: person(:member2))

      purge = Housekeeping.purge(:field_answers)
      assert_equal 36, purge.months
      records = purge.records(purge.default_cutoff)
      assert_equal [ [ person(:member).display_name, "Allergies" ] ], purge.describe(records)

      purge.run!(cutoff: purge.default_cutoff, by: person(:admin))
      assert_not PersonFieldValue.exists?(person: person(:member), person_field: allergies)
      assert PersonFieldValue.exists?(person: person(:member), person_field: shirt, value: "M")
      assert PersonFieldValue.exists?(person: person(:member2), person_field: allergies, value: "Peanuts")
    end
  end

  test "the field answers purge counts answers and people apart" do
    with_housekeeping(feature_person_fields: "true", housekeeping_purge_fields: "Medical") do
      group = PersonFieldGroup.create!(name: "Medical")
      fields = %w[Allergies Medications].map { |name| PersonField.create!(name: name, key: name.downcase, person_field_group: group) }
      person(:member).update_columns(created_at: 4.years.ago)
      fields.each { |field| PersonFieldValue.create!(person: person(:member), person_field: field, value: "Some") }

      purge = Housekeeping.purge(:field_answers)
      records = purge.records(purge.default_cutoff)
      assert_equal "2 answers from 1 person", purge.summary(records)
      assert_equal 1, purge.row_count(records)
      assert_equal [ [ person(:member).display_name, "Allergies and Medications" ] ], purge.describe(records)
    end
  end

  test "the field answers purge clears nothing until fields are named" do
    with_housekeeping(feature_person_fields: "true", housekeeping_purge_fields: "") do
      assert_empty Housekeeping.purge(:field_answers).records(Date.current)
    end
  end

  # Move people

  test "moving people replaces their membership, skipping managers and people not directly in the team" do
    alumni = create_world_team("Alumni", parent: @org)
    move = Housekeeping::MovePeople.new(from: @members, to: alumni, people: [ person(:member), person(:outsider) ])
    assert_equal [ person(:member) ], move.ready
    assert_equal "not a direct member of Members", move.skipped.first.reason
    assert_equal "1 person will move from Members to Alumni. 1 skipped.", move.sentence

    move.apply!
    assert_not @members.memberships.exists?(person: person(:member))
    assert alumni.memberships.exists?(person: person(:member))

    Membership.find_by!(team: @club, person: person(:club_manager))
    managers = Housekeeping::MovePeople.new(from: @club, to: alumni, people: [ person(:club_manager) ])
    assert_equal "manages Club", managers.skipped.first.reason
  end

  test "moving 150 people marks each checklist once, not once per person" do
    with_settings(feature_checklists: "true") do
      alumni = create_world_team("Alumni", parent: @org)
      checklists = Array.new(10) { |index| create_world_checklist("List #{index}").tap { |checklist| add_rule(checklist, :include, :team, team_id: @members.id) } }
      people = Array.new(150) { |index| Person.create!(first_name: "Mover#{index}", last_name: "World") }
      Membership.insert_all(people.map { |mover| { person_id: mover.id, team_id: @members.id, created_at: Time.current, updated_at: Time.current } })
      ChecklistRefresh.delete_all

      queries = []
      counter = ->(*, payload) { queries << payload[:sql] unless payload[:name] == "SCHEMA" }
      ActiveSupport::Notifications.subscribed(counter, "sql.active_record") do
        Housekeeping::MovePeople.new(from: @members, to: alumni, people: people).apply!
      end

      marking = queries.grep(/checklist/i)
      assert_operator marking.size, :<=, 5 * checklists.size + 10, "marking should cost a few queries per checklist"
      assert_operator queries.size, :<, 150 * 20, "the move itself stays a handful of queries per person"
      checklists.each do |checklist|
        assert_equal 150, ChecklistRefresh.where(checklist: checklist, person_id: people.map(&:id)).count
      end
      assert_equal 150, alumni.memberships.count
    end
  end

  test "only admins and managers of both teams may move people" do
    alumni = create_world_team("Alumni", parent: @other_org)
    assert Housekeeping::MovePeople.allowed?(user(:admin), @members, alumni)
    assert_not Housekeeping::MovePeople.allowed?(user(:club_manager), @members, alumni)

    Membership.create!(team: alumni, person: person(:club_manager), manager: true)
    assert Housekeeping::MovePeople.allowed?(user(:club_manager), @members, alumni)
  end
end
