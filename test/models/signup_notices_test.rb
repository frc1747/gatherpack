require "test_helper"
require_relative "../support/signups_world"

# Sign-up notices (spec §3.7): confirmation, reminders, event time changes,
# and the signup_changed / signup_sheet_changed notifications (§3.9).
class SignupNoticesTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper
  include SignupsWorld

  setup do
    travel_to Time.zone.parse("2026-10-11 12:00")
    build_signups_world
    @sheet = create_world_sheet
    @cashier = @sheet.signup_positions.create!(name: "Cashier", capacity: 4)
    clear_enqueued_jobs
  end

  test "a sign-up is confirmed to the person, the signer and whoever it's on behalf of" do
    Signup.place!(slot: slot_for(@cashier), person: person(:student), signed_up_by: person(:admin), on_behalf_of: person(:sibling))

    assert_equal [ email_of(:admin), email_of(:sibling), email_of(:student) ].sort, enqueued_email_addresses
    address, subject, body = enqueued_emails.first
    assert_match "Signed up: Cashier, Game Day", subject
    assert_match "Snack Stand", body
    assert_match "On behalf of Sibling World", body
    assert address.present?
  end

  test "someone signing themselves up gets one confirmation, and people without an address none" do
    Signup.place!(slot: slot_for(@cashier), person: person(:student), signed_up_by: person(:student))
    assert_equal [ email_of(:student) ], enqueued_email_addresses

    clear_enqueued_jobs
    no_email = Person.create!(first_name: "Nomail", last_name: "World")
    Membership.create!(person: no_email, team: @students)
    Signup.place!(slot: slot_for(@cashier), person: no_email, signed_up_by: no_email)
    assert_empty enqueued_emails
  end

  test "with no email gateway set up, sending does nothing and nothing fails" do
    assert_nil Gateway[:email_sending]

    assert_nothing_raised do
      capture_io do
        perform_enqueued_jobs do
          Signup.place!(slot: slot_for(@cashier), person: person(:student), signed_up_by: person(:student))
        end
      end
    end
  end

  test "a reminder is scheduled the sheet's reminder days before the event" do
    signup = Signup.place!(slot: slot_for(@cashier), person: person(:student), signed_up_by: person(:student))

    assert_enqueued_with(job: SignupReminderJob, args: [ signup, @event.id, @event.start_time.iso8601 ], at: @event.start_time - 2.days)
  end

  test "no reminder when the sheet sends none or it's already too late" do
    @sheet.update!(reminder_days: 0)
    Signup.place!(slot: slot_for(@cashier), person: person(:student), signed_up_by: person(:student))
    assert_no_enqueued_jobs only: SignupReminderJob

    @sheet.update!(reminder_days: 30)
    Signup.place!(slot: slot_for(@cashier), person: person(:student2), signed_up_by: person(:student2))
    assert_no_enqueued_jobs only: SignupReminderJob
  end

  test "the reminder goes out if the sign-up and the event's time still stand" do
    signup = create_world_signup(@cashier, :student)
    clear_enqueued_jobs

    SignupReminderJob.perform_now(signup, @event.id, @event.start_time.iso8601)

    assert_equal [ email_of(:student) ], enqueued_email_addresses
    assert_match "Reminder: Cashier, Game Day", enqueued_emails.first[1]
  end

  test "the reminder does nothing once the sign-up is cancelled or the event has moved" do
    signup = create_world_signup(@cashier, :student)
    start = @event.start_time.iso8601
    @event.update!(start_time: @event.start_time + 1.day, end_time: @event.end_time + 1.day)
    clear_enqueued_jobs

    # As the job would, with the sign-up loaded afresh.
    SignupReminderJob.perform_now(Signup.find(signup.id), @event.id, start)
    assert_empty enqueued_emails

    signup.cancel!
    SignupReminderJob.perform_now(Signup.find(signup.id), @event.id, @event.start_time.iso8601)
    assert_empty enqueued_emails
  end

  test "changing an event's time tells everyone with an active sign-up and moves their reminders" do
    active = create_world_signup(@cashier, :student, signed_up_by: person(:parent))
    create_world_signup(@cashier, :student2, status: :cancelled)
    clear_enqueued_jobs

    @event.update!(start_time: Time.zone.parse("2026-10-24 13:00"), end_time: Time.zone.parse("2026-10-24 17:00"))

    assert_equal [ email_of(:parent), email_of(:student) ].sort, enqueued_email_addresses
    _, subject, body = enqueued_emails.first
    assert_match "Time changed: Game Day", subject
    assert_match "Sat Oct 24, 2026, 10:00 AM to 2:00 PM", body
    assert_match "Sat Oct 24, 2026, 1:00 PM to 5:00 PM", body
    assert_enqueued_with(job: SignupReminderJob, args: [ active, @event.id, @event.start_time.iso8601 ])
  end

  test "an event entered as 00:00 to 23:59 getting its real time is a time change" do
    placeholder = create_world_event("Picnic", Time.zone.parse("2026-11-07 00:00"))
    placeholder.update!(end_time: Time.zone.parse("2026-11-07 23:59"))
    @sheet.signup_sheet_events.create!(event: placeholder)
    create_world_signup(@cashier, :student, event: placeholder)
    clear_enqueued_jobs

    placeholder.update!(start_time: Time.zone.parse("2026-11-07 11:00"), end_time: Time.zone.parse("2026-11-07 15:00"))

    assert_equal [ email_of(:student) ], enqueued_email_addresses
    assert_match "It was: Sat Nov 7, 2026, time not set yet", enqueued_emails.first[2]
  end

  test "changing an event's name or place sends nothing" do
    create_world_signup(@cashier, :student)
    clear_enqueued_jobs

    @event.update!(name: "Homecoming", location: "Field 2")

    assert_empty enqueued_emails
  end

  test "an organizer's message goes to each person signed up for the date, one email each" do
    create_world_signup(@cashier, :student, signed_up_by: person(:parent))
    create_world_signup(@cashier, :student2, status: :fulfilled)
    create_world_signup(@cashier, :sibling, status: :cancelled)
    clear_enqueued_jobs

    sent = SignupNotices.new.message(@sheet, @event, subject: "Parking", body: "Park <b>behind</b> the gym.\n\nThanks!", from: person(:worker))

    assert_equal 3, sent
    assert_equal [ email_of(:parent), email_of(:student), email_of(:student2) ].sort, enqueued_email_addresses
    _, subject, body = enqueued_emails.first
    assert_match "Parking", subject
    assert_match "Park &lt;b&gt;behind&lt;/b&gt; the gym.", body
    assert_match "From Worker World", body
  end

  test "sign-up changes are announced as signup_changed.gatherpack" do
    changes = capture_notifications("signup_changed.gatherpack") do
      signup = Signup.place!(slot: slot_for(@cashier), person: person(:student), signed_up_by: person(:student))
      bar = @sheet.signup_positions.create!(name: "Bar")
      signup.change!(by: person(:admin), slot: slot_for(bar))
      signup.change!(by: person(:admin), note: "Only a note")
      signup.cancel!
    end

    assert_equal %i[ created moved cancelled ], changes.map { |payload| payload[:change] }
  end

  test "changes to a sheet's positions, slots and events are announced as signup_sheet_changed.gatherpack" do
    changes = capture_notifications("signup_sheet_changed.gatherpack") do
      bar = @sheet.signup_positions.create!(name: "Bar")
      slot_for(bar).update!(capacity: 3)
      @event.update!(start_time: @event.start_time + 1.hour)
    end

    assert changes.all? { |payload| payload[:signup_sheet_id] == @sheet.id }
    records = changes.map { |payload| [ payload[:record].class.name, payload[:change] ] }
    assert_includes records, [ "SignupPosition", :created ]
    assert_includes records, [ "SignupSlot", :created ]
    assert_includes records, [ "SignupSlot", :updated ]
    assert_includes records, [ "Event", :event_time ]
  end

  test "an event's time reads as not set when it runs 00:00 to 23:59" do
    assert SignupNotices.time_unset?(Time.zone.parse("2026-11-07 00:00"), Time.zone.parse("2026-11-07 23:59"))
    assert_not SignupNotices.time_unset?(Time.zone.parse("2026-11-07 00:00"), Time.zone.parse("2026-11-07 12:00"))
    assert_not SignupNotices.time_unset?(Time.zone.parse("2026-11-07 00:00"), nil)
  end

  private

  def capture_notifications(name, &block)
    payloads = []
    ActiveSupport::Notifications.subscribed(->(*, payload) { payloads << payload }, name, &block)
    payloads
  end
end
