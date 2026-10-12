require "test_helper"
require_relative "../support/signups_world"

# What organizers do around an event: Mark all brought for items, notices
# when they cancel or move a sign-up, and messaging everyone signed up for
# a date (spec §3.5, §3.6, §3.7). worker and concessions_manager organize.
class SignupOrganizerNoticesTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper
  include Devise::Test::IntegrationHelpers
  include SignupsWorld

  setup do
    host! "localhost"
    travel_to Time.zone.parse("2026-10-24 16:00")
    build_signups_world
    @restore_settings = apply_settings(signups_organizers: "Sheet Organizer > Club")
    BadgeAssignment.create!(badge: @organizer_badge, person: person(:concessions_manager))
    @sheet = create_world_sheet(created_by: person(:worker))
    @sheet.signup_sheet_organizers.create!(person: person(:concessions_manager))
    @cashier = @sheet.signup_positions.create!(name: "Cashier", capacity: 4)
    @dessert = @sheet.signup_positions.create!(name: "Dessert", kind: :items, unit: "pies", capacity: 10)
    RelationshipType.create!(parent_label: "Spouse of", child_label: "Spouse of", permission: :added_by_admin).then do |spouse|
      Relationship.create!(parent: person(:worker), child: person(:parent), relationship_type: spouse, created_by: person(:admin))
    end
    clear_enqueued_jobs
  end

  teardown do
    @restore_settings&.call
  end

  test "Mark all brought marks the event's item sign-ups, leaving the organizer's own and their relatives' (decision 14)" do
    later = create_world_event("Second Game", Time.zone.parse("2026-10-31 10:00"))
    @sheet.signup_sheet_events.create!(event: later)
    pie = create_world_signup(@dessert, :student, quantity: 2)
    own = create_world_signup(@dessert, :worker, quantity: 1)
    spouse = create_world_signup(@dessert, :parent, quantity: 1)
    worker_for_someone = create_world_signup(@dessert, :student2, quantity: 1, on_behalf_of: person(:worker))
    cashier = create_world_signup(@cashier, :student)
    next_week = create_world_signup(@dessert, :sibling, event: later, quantity: 1)
    sign_in person(:worker).user

    patch mark_all_brought_signup_sheet_roster_signups_path(@sheet), params: { event_id: @event.id }

    assert_redirected_to roster_signup_sheet_path(@sheet, event_id: @event.id)
    assert_equal "1 sign-up at Game Day marked brought. 3 sign-ups left: another organizer needs to mark your own family's sign-ups.", flash[:notice]
    assert pie.reload.fulfilled?
    [ own, spouse, worker_for_someone, cashier, next_week ].each { |signup| assert signup.reload.active?, signup.identifier_name }

    sign_in person(:concessions_manager).user
    patch mark_all_brought_signup_sheet_roster_signups_path(@sheet), params: { event_id: @event.id }
    [ own, spouse, worker_for_someone ].each { |signup| assert signup.reload.fulfilled?, signup.identifier_name }
  end

  test "the roster offers Mark all brought only when the sheet has items" do
    sign_in person(:worker).user

    get roster_signup_sheet_path(@sheet)
    assert_select "form#mark_all_brought"

    @dessert.destroy!
    get roster_signup_sheet_path(@sheet)
    assert_select "form#mark_all_brought", count: 0
  end

  test "only the sheet's organizers can Mark all brought" do
    pie = create_world_signup(@dessert, :student, quantity: 2)

    [ :student, :parent, :outsider ].each do |name|
      sign_in person(name).user
      patch mark_all_brought_signup_sheet_roster_signups_path(@sheet), params: { event_id: @event.id }
      assert_redirected_to root_path, name.to_s
      sign_out :user
    end
    assert pie.reload.active?
  end

  test "an organizer cancelling a sign-up tells the people on it" do
    signup = create_world_signup(@cashier, :student, signed_up_by: person(:parent))
    clear_enqueued_jobs
    sign_in person(:worker).user

    delete signup_sheet_roster_signup_path(@sheet, signup)

    assert signup.reload.cancelled?
    assert_equal [ email_of(:parent), email_of(:student) ].sort, enqueued_email_addresses
    assert_match "Worker World cancelled Student World&#39;s sign-up", enqueued_emails.first[2]
  end

  test "cancelling a sign-up that's already cancelled sends nothing again" do
    signup = create_world_signup(@cashier, :student, status: :cancelled)
    clear_enqueued_jobs
    sign_in person(:worker).user

    delete signup_sheet_roster_signup_path(@sheet, signup)

    assert_redirected_to roster_signup_sheet_path(@sheet)
    assert_equal "Student World's sign-up was already cancelled.", flash[:alert]
    assert_empty enqueued_emails
  end

  test "a member cancelling their own sign-up gets no notice" do
    travel_to Time.zone.parse("2026-10-20 12:00")
    signup = create_world_signup(@cashier, :student)
    clear_enqueued_jobs
    sign_in person(:student).user

    delete signup_sheet_signup_path(@sheet, signup)

    assert signup.reload.cancelled?
    assert_empty enqueued_emails
  end

  test "an organizer moving a sign-up tells the people on it, and moves the reminder" do
    travel_to Time.zone.parse("2026-10-11 12:00")
    later = create_world_event("Second Game", Time.zone.parse("2026-10-31 10:00"))
    @sheet.signup_sheet_events.create!(event: later)
    signup = create_world_signup(@cashier, :student)
    clear_enqueued_jobs
    sign_in person(:worker).user

    patch move_signup_sheet_roster_signup_path(@sheet, signup), params: { signup: { signup_slot_id: slot_for(@cashier, later).id } }

    assert_redirected_to roster_signup_sheet_path(@sheet)
    assert_equal [ email_of(:student) ], enqueued_email_addresses
    _, subject, body = enqueued_emails.first
    assert_match "Sign-up moved: Cashier, Second Game", subject
    assert_match "It was: Cashier, Game Day", body
    assert_enqueued_with(job: SignupReminderJob, args: [ signup, slot_for(@cashier, later).id, later.start_time.iso8601 ])
  end

  test "an organizer messages everyone signed up for a date without seeing their addresses" do
    create_world_signup(@cashier, :student, signed_up_by: person(:parent))
    create_world_signup(@dessert, :student2, quantity: 1)
    create_world_signup(@cashier, :sibling, status: :cancelled)
    clear_enqueued_jobs
    sign_in person(:worker).user

    get new_signup_sheet_signup_message_path(@sheet, event_id: @event.id)
    assert_response :success
    assert_select "select[name=event_id] option[selected][value=?]", @event.id
    assert_no_match "@example.com", response.body

    post signup_sheet_signup_messages_path(@sheet), params: { event_id: @event.id, subject: "Parking", body: "Use the back lot." }

    assert_redirected_to roster_signup_sheet_path(@sheet, event_id: @event.id)
    assert_equal "Message sent to 3 people.", flash[:notice]
    assert_equal [ email_of(:parent), email_of(:student), email_of(:student2) ].sort, enqueued_email_addresses
    follow_redirect!
    assert_no_match "@example.com", response.body.gsub(person(:worker).user.email, "")
  end

  test "a message needs a date of the sheet, a subject and a body" do
    other = create_world_event("Elsewhere", Time.zone.parse("2026-10-30 10:00"))
    sign_in person(:worker).user

    post signup_sheet_signup_messages_path(@sheet), params: { event_id: other.id, subject: "Hi", body: "Hello" }
    assert_response :unprocessable_entity
    assert_select ".alert-danger", text: "Pick a date."

    post signup_sheet_signup_messages_path(@sheet), params: { event_id: @event.id, subject: "", body: "Hello" }
    assert_response :unprocessable_entity
    assert_select ".alert-danger", text: "Write a subject and a message."
    assert_empty enqueued_emails
  end

  test "with no one to send to, the organizer is told nothing was sent" do
    sign_in person(:worker).user

    post signup_sheet_signup_messages_path(@sheet), params: { event_id: @event.id, subject: "Hi", body: "Hello" }

    assert_equal "No one signed up for Game Day has an email address, so nothing was sent.", flash[:alert]
  end

  test "only the sheet's organizers can message the people signed up" do
    create_world_signup(@cashier, :student)
    clear_enqueued_jobs

    [ :student, :parent, :outsider ].each do |name|
      sign_in person(name).user
      get new_signup_sheet_signup_message_path(@sheet)
      assert_redirected_to root_path, name.to_s
      post signup_sheet_signup_messages_path(@sheet), params: { event_id: @event.id, subject: "Hi", body: "Hello" }
      assert_redirected_to root_path, name.to_s
      sign_out :user
    end
    assert_empty enqueued_emails
  end
end
