require "test_helper"
require_relative "../support/signups_world"

# Check-ins fulfil sign-ups (spec §3.5, decisions 7 and 13), through the
# callback config/initializers/signups.rb adds to Checkin.
class SignupCheckinTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper
  include SignupsWorld

  setup do
    travel_to Time.zone.parse("2026-10-24 09:00")
    build_signups_world
    @sheet = create_world_sheet
    @cashier = @sheet.signup_positions.create!(name: "Cashier", capacity: 4)
    @dessert = @sheet.signup_positions.create!(name: "Dessert", kind: :items, unit: "pies", capacity: 6)
  end

  test "Checkin gets the callback from the initializer, not from checkin.rb" do
    assert Checkin.include?(Signups::CheckinFulfilment)
    assert_no_match(/signup/i, Rails.root.join("app/models/checkin.rb").read)
  end

  test "a check-in fulfils the person's active people sign-ups at that event" do
    signup = create_world_signup(@cashier, :student)
    other = create_world_signup(@cashier, :student2)

    Checkin.create!(person: person(:student), event: @event)

    assert signup.reload.fulfilled?
    assert other.reload.active?
  end

  test "a check-in never creates a sign-up" do
    assert_no_difference "Signup.count" do
      Checkin.create!(person: person(:student), event: @event)
    end
  end

  test "a check-in doesn't fulfil item sign-ups" do
    pie = create_world_signup(@dessert, :student, quantity: 2)

    Checkin.create!(person: person(:student), event: @event)

    assert pie.reload.active?
  end

  test "a check-in leaves sign-ups at other events and cancelled ones alone" do
    later = create_world_event("Second Game", Time.zone.parse("2026-10-31 10:00"))
    @sheet.signup_sheet_events.create!(event: later)
    elsewhere = create_world_signup(@cashier, :student, event: later)
    cancelled = create_world_signup(@cashier, :student, status: :cancelled)

    Checkin.create!(person: person(:student), event: @event)

    assert elsewhere.reload.active?
    assert cancelled.reload.cancelled?
  end

  test "check-in means the person taking the place showed up, not whoever it's on behalf of (decision 13)" do
    signup = create_world_signup(@cashier, :parent, on_behalf_of: person(:student))

    Checkin.create!(person: person(:student), event: @event)
    assert signup.reload.active?, "the on-behalf-of person's check-in doesn't fulfil it"

    Checkin.create!(person: person(:parent), event: @event)
    assert signup.reload.fulfilled?
  end

  test "fulfilling from a check-in runs the fulfilled hook and announces the change" do
    signup = create_world_signup(@cashier, :student)
    Hook.create!(name: "Fulfilled", event: "signups - fulfilled", code: "Thread.current[:signup_hooks] << model.id")
    Thread.current[:signup_hooks] = []
    changes = []
    callback = ->(*, payload) { changes << [ payload[:signup], payload[:change] ] }

    ActiveSupport::Notifications.subscribed(callback, "signup_changed.gatherpack") do
      Checkin.create!(person: person(:student), event: @event)
    end

    assert_equal [ signup.id ], Thread.current[:signup_hooks]
    assert_includes changes, [ signup, :status ]
  ensure
    Thread.current[:signup_hooks] = nil
  end
end
