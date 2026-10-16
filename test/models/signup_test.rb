require "test_helper"
require_relative "../support/signups_world"

class SignupTest < ActiveSupport::TestCase
  include SignupsWorld

  setup do
    build_signups_world
    @sheet = create_world_sheet
    @cashier = @sheet.signup_positions.create!(name: "Cashier", capacity: 3)
    @pizza = @sheet.signup_positions.create!(name: "Pizza", kind: :items, unit: "pizzas", capacity: 6)
  end

  test "each people sign-up uses one place" do
    slot = slot_for(@cashier)
    slot.update!(capacity: 2)
    Signup.place!(slot: slot, person: person(:student), signed_up_by: person(:student))

    assert_equal 1, slot.used
    assert_equal 1, slot.remaining
    assert_not slot.full?

    place(slot, :student2)
    assert slot.full?
    error = assert_raises(ActiveRecord::RecordInvalid) { place(slot, :worker) }
    assert_match "This slot is full", error.message
  end

  test "an item sign-up uses its quantity" do
    slot = slot_for(@pizza)
    place(slot, :student, quantity: 4)

    error = assert_raises(ActiveRecord::RecordInvalid) { place(slot, :student2, quantity: 3) }
    assert_match "Only 2 pizzas still needed", error.message

    error = assert_raises(ActiveRecord::RecordInvalid) { place(slot, :student2) }
    assert_match "Quantity is needed", error.message
    error = assert_raises(ActiveRecord::RecordInvalid) { place(slot_for(@cashier), :student2, quantity: 1) }
    assert_match "only for item positions", error.message

    place(slot, :student2, quantity: 2)
    assert slot.full?
  end

  test "cancelled and no-show sign-ups don't use the slot" do
    slot = slot_for(@cashier)
    slot.update!(capacity: 1)
    first = place(slot, :student)
    assert slot.full?

    first.cancel!
    assert_equal 0, slot.used
    second = place(slot, :student2)
    second.no_show!
    assert_equal 0, slot.used
  end

  test "a position with no cap takes any number" do
    @cashier.update!(capacity: nil)
    slot = slot_for(@cashier)
    place(slot, :student)
    place(slot, :student2)
    place(slot, :worker)

    assert_nil slot.capacity_value
    assert_nil slot.remaining
    assert_not slot.full?
  end

  test "a slot can override the position's cap or be turned off" do
    slot = slot_for(@cashier)
    slot.update!(capacity: 1)
    place(slot, :student)
    assert slot.full?

    slot.update!(capacity: nil, disabled: true)
    error = assert_raises(ActiveRecord::RecordInvalid) { place(slot, :student2) }
    assert_match "This slot is turned off", error.message
  end

  test "an edit leaves out the sign-up's own usage" do
    slot = slot_for(@cashier)
    slot.update!(capacity: 2)
    signup = place(slot, :student)
    place(slot, :student2)

    signup.change!(by: person(:student), note: "Same place")
    assert_equal "Same place", signup.reload.note

    item = place(slot_for(@pizza), :student, quantity: 6)
    item.change!(by: person(:student), quantity: 5)
    item.change!(by: person(:student), quantity: 6)
    assert_equal 6, item.reload.quantity
  end

  test "an edit that doesn't grow a sign-up works on a slot over its cap" do
    slot = slot_for(@cashier)
    signup = place(slot, :student)
    place(slot, :student2)
    slot.update!(capacity: 1)

    signup.change!(by: person(:student), note: "Running late")
    assert_equal "Running late", signup.reload.note
  end

  test "members sign up only on open sheets; organizers on any but archived" do
    @sheet.closed!
    error = assert_raises(ActiveRecord::RecordInvalid) { place(slot_for(@cashier), :student) }
    assert_match "isn't open", error.message

    Signup.place!(slot: slot_for(@cashier), person: person(:student), signed_up_by: person(:admin))

    @sheet.archived!
    error = assert_raises(ActiveRecord::RecordInvalid) { Signup.place!(slot: slot_for(@cashier), person: person(:student2), signed_up_by: person(:admin)) }
    assert_match "archived", error.message
  end

  test "members can only sign up people they can sign up, on behalf of people the sheet allows" do
    slot = slot_for(@cashier)
    error = assert_raises(ActiveRecord::RecordInvalid) { Signup.place!(slot: slot, person: person(:student), signed_up_by: person(:parent)) }
    assert_match "You can't sign up Student World", error.message

    @sheet.update!(others_relationship_type_ids: [ @parent_of.id ])
    signup = Signup.place!(slot: slot, person: person(:student), signed_up_by: person(:parent))
    assert_equal person(:student), signup.on_behalf_of

    error = assert_raises(ActiveRecord::RecordInvalid) { Signup.place!(slot: slot, person: person(:student2), signed_up_by: person(:student2), on_behalf_of: person(:student)) }
    assert_match "on behalf of Student World", error.message

    @sheet.on_behalf_of_anyone!
    assert Signup.place!(slot: slot, person: person(:student2), signed_up_by: person(:student2), on_behalf_of: person(:student)).persisted?
  end

  test "eligibility blocks members; organizers can override for others but not their family" do
    @cashier.signup_position_rules.create!(kind: :badge, badge_ids: [ @license_badge.id ])
    slot = slot_for(@cashier)

    error = assert_raises(ActiveRecord::RecordInvalid) { place(slot, :student) }
    assert_match "Needs the Alcohol License badge", error.message
    error = assert_raises(ActiveRecord::RecordInvalid) { Signup.place!(slot: slot, person: person(:student), signed_up_by: person(:student), override_rules: true) }
    assert_match "Only organizers", error.message

    assert Signup.place!(slot: slot, person: person(:student), signed_up_by: person(:admin), override_rules: true).persisted?

    Relationship.create!(parent: person(:admin), child: person(:student2), relationship_type: @parent_of, created_by: person(:admin))
    error = assert_raises(ActiveRecord::RecordInvalid) { Signup.place!(slot: slot, person: person(:student2), signed_up_by: person(:admin), override_rules: true) }
    assert_match "Another organizer", error.message
  end

  test "a required answer" do
    @pizza.update!(question: "What kind?", question_required: true)

    error = assert_raises(ActiveRecord::RecordInvalid) { place(slot_for(@pizza), :student, quantity: 1) }
    assert_match "Answer \"What kind?\"", error.message
    assert place(slot_for(@pizza), :student, quantity: 1, answer: "Cheese").persisted?
  end

  test "a sign-up can move to another slot on the sheet" do
    second = create_world_event("Second Game", Time.zone.parse("2026-10-31 10:00"))
    @sheet.signup_sheet_events.create!(event: second)
    signup = place(slot_for(@cashier), :student)
    slot_for(@cashier, second).update!(capacity: 1)
    place(slot_for(@cashier, second), :student2)

    error = assert_raises(ActiveRecord::RecordInvalid) { signup.change!(by: person(:admin), slot: slot_for(@cashier, second)) }
    assert_match "This slot is full", error.message

    third = create_world_event("Third Game", Time.zone.parse("2026-11-07 10:00"))
    @sheet.signup_sheet_events.create!(event: third)
    signup.reload.change!(by: person(:admin), slot: slot_for(@cashier, third))
    assert_equal slot_for(@cashier, third), signup.reload.signup_slot
    assert_equal 0, slot_for(@cashier).used

    other_sheet = create_world_sheet("Other")
    other_slot = slot_for(other_sheet.signup_positions.create!(name: "Usher"))
    error = assert_raises(ActiveRecord::RecordInvalid) { signup.reload.change!(by: person(:admin), slot: other_slot) }
    assert_match "only move within its sheet", error.message
  end

  test "members can cancel until the cutoff before the event starts" do
    signup = place(slot_for(@cashier), :student)
    start = @event.start_time

    assert signup.cancellable_by_member?(start - 1.minute)
    assert_not signup.cancellable_by_member?(start)

    @sheet.update!(cancel_cutoff_hours: 24)
    assert signup.reload.cancellable_by_member?(start - 25.hours)
    assert_not signup.cancellable_by_member?(start - 23.hours)

    signup.cancel!
    assert_not signup.cancellable_by_member?(start - 25.hours)
  end

  test "hooks fire when a sign-up is fulfilled or cancelled" do
    Hook.create!(name: "Fulfilled", event: "signups - fulfilled", code: "Thread.current[:signup_hooks] << [ :fulfilled, model.id ]")
    Hook.create!(name: "Cancelled", event: "signups - cancelled", code: "Thread.current[:signup_hooks] << [ :cancelled, model.id ]")
    Thread.current[:signup_hooks] = []

    first = place(slot_for(@cashier), :student)
    second = place(slot_for(@cashier), :student2)
    assert_empty Thread.current[:signup_hooks]

    first.fulfilled!
    second.cancel!
    first.update!(note: "Thanks")
    assert_equal [ [ :fulfilled, first.id ], [ :cancelled, second.id ] ], Thread.current[:signup_hooks]
    assert_includes Hook.catalog, "signups - fulfilled"
    assert_includes Hook.catalog, "signup_slots - update"
  ensure
    Thread.current[:signup_hooks] = nil
  end

  private

  def place(slot, name, **options)
    Signup.place!(slot: slot, person: person(name), signed_up_by: person(name), **options)
  end
end
