require "test_helper"
require_relative "../support/signups_world"

# The roster (SignupSheetsController#roster) and the organizer actions on it.
# worker runs the sheet; concessions_manager is a second organizer.
class RosterSignupsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include SignupsWorld

  setup do
    host! "localhost"
    build_signups_world
    @restore_settings = apply_settings(signups_organizers: "Sheet Organizer > Club")
    BadgeAssignment.create!(badge: @organizer_badge, person: person(:concessions_manager))
    @sheet = create_world_sheet(created_by: person(:worker))
    @sheet.signup_sheet_organizers.create!(person: person(:concessions_manager))
    @cashier = @sheet.signup_positions.create!(name: "Cashier", capacity: 4)
    @bar = @sheet.signup_positions.create!(name: "Bar", capacity: 2)
    @bar.signup_position_rules.create!(kind: :badge, badge_ids: [ @license_badge.id ])
  end

  teardown do
    @restore_settings&.call
  end

  test "an organizer sees the roster with names, details and filters" do
    second = create_world_event("Second Game", Time.zone.parse("2026-10-31 10:00"))
    @sheet.signup_sheet_events.create!(event: second)
    place(@cashier, :student, extra_people: 2, extra_names: "Sam, Alex", note: "Leaves early", answer: "Yes")
    place(@cashier, :student2, event: second)
    cancelled = place(@cashier, :parent)
    cancelled.cancel!
    sign_in person(:worker).user

    get roster_signup_sheet_path(@sheet)
    assert_response :success
    assert_select "#roster tbody tr", count: 3
    assert_select "td", text: "2 extra: Sam, Alex"
    assert_select "td", text: "Leaves early"
    assert_select "button", text: "Print"
    assert_select "td", text: person(:student).birthday.to_s, count: 0

    get roster_signup_sheet_path(@sheet, event_id: second.id)
    assert_select "#roster tbody tr", count: 1
    assert_select "td", text: person(:student2).display_name

    get roster_signup_sheet_path(@sheet, status: "cancelled")
    assert_select "#roster tbody tr", count: 1
    assert_select "td", text: person(:parent).display_name

    get roster_signup_sheet_path(@sheet, signup_position_id: @bar.id)
    assert_select "#roster", count: 0
    assert_select "p", text: "No sign-ups match these filters."
  end

  test "an organizer places someone, overriding a rule, and the roster flags it" do
    sign_in person(:worker).user
    slot = slot_for(@bar)

    get new_signup_sheet_roster_signup_path(@sheet, signup_slot_id: slot.id)
    assert_response :success

    assert_no_difference "Signup.count" do
      post signup_sheet_roster_signups_path(@sheet), params: { signup: { signup_slot_id: slot.id, person_id: person(:student).id, note: "Cover" } }
    end
    assert_response :unprocessable_entity
    assert_select "label", text: /Place even though they don't meet: Needs the Alcohol License badge/

    assert_difference "Signup.count" do
      post signup_sheet_roster_signups_path(@sheet), params: { signup: { signup_slot_id: slot.id, person_id: person(:student).id, note: "Cover", override_rules: "1" } }
    end
    assert_redirected_to roster_signup_sheet_path(@sheet)
    signup = Signup.order(:created_at).last
    assert_equal [ person(:student), person(:worker), "Cover" ], [ signup.person, signup.signed_up_by, signup.note ]

    get roster_signup_sheet_path(@sheet)
    assert_select "##{ActionView::RecordIdentifier.dom_id(signup)} td", text: "Placed without: Needs the Alcohol License badge"
  end

  test "an organizer can only place people the sheet is open to" do
    sign_in person(:worker).user

    assert_no_difference "Signup.count" do
      post signup_sheet_roster_signups_path(@sheet), params: { signup: { signup_slot_id: slot_for(@cashier).id, person_id: person(:outsider).id } }
    end
    assert_response :unprocessable_entity
  end

  test "an organizer can't override a rule for themselves or a relative, but another organizer can" do
    @cashier.signup_position_rules.create!(kind: :age, max_age: 17)
    relate_to_worker(:student2)
    sign_in person(:worker).user

    [ :worker, :student2 ].each do |name|
      assert_no_difference "Signup.count" do
        post signup_sheet_roster_signups_path(@sheet), params: { signup: { signup_slot_id: slot_for(@cashier).id, person_id: person(name).id, override_rules: "1" } }
      end
    end

    sign_in person(:concessions_manager).user
    assert_difference "Signup.count" do
      post signup_sheet_roster_signups_path(@sheet), params: { signup: { signup_slot_id: slot_for(@cashier).id, person_id: person(:worker).id, override_rules: "1" } }
    end
  end

  test "an organizer can't mark or move their own or a relative's sign-up, and the roster says why" do
    relate_to_worker(:student2)
    own = place(@cashier, :worker)
    relative = place(@cashier, :student2)
    sign_in person(:worker).user

    get roster_signup_sheet_path(@sheet)
    assert_select "##{ActionView::RecordIdentifier.dom_id(own)}", text: /#{SignupSheet::SELF_APPROVAL_REASON}/
    assert_select "##{ActionView::RecordIdentifier.dom_id(own)} button", text: "Fulfilled", count: 0

    [ own, relative ].each do |signup|
      patch mark_signup_sheet_roster_signup_path(@sheet, signup), params: { status: "fulfilled" }
      patch move_signup_sheet_roster_signup_path(@sheet, signup), params: { signup: { signup_slot_id: slot_for(@bar).id } }
      signup.reload
      assert signup.active?
      assert_equal @cashier, signup.signup_position
    end

    sign_in person(:concessions_manager).user
    patch mark_signup_sheet_roster_signup_path(@sheet, own), params: { status: "fulfilled" }
    assert own.reload.fulfilled?
    patch move_signup_sheet_roster_signup_path(@sheet, relative), params: { signup: { signup_slot_id: slot_for(@bar).id, override_rules: "1" } }
    assert_equal @bar, relative.reload.signup_position
  end

  test "an organizer edits, moves and cancels a sign-up" do
    signup = place(@cashier, :student)
    sign_in person(:worker).user

    get edit_signup_sheet_roster_signup_path(@sheet, signup)
    assert_response :success
    patch signup_sheet_roster_signup_path(@sheet, signup), params: { signup: { extra_people: "1", extra_names: "Sam", note: "Late" } }
    assert_redirected_to roster_signup_sheet_path(@sheet)
    assert_equal [ 1, "Sam", "Late" ], signup.reload.values_at(:extra_people, :extra_names, :note)

    patch move_signup_sheet_roster_signup_path(@sheet, signup), params: { signup: { signup_slot_id: slot_for(@bar).id } }
    assert_response :unprocessable_entity
    assert_select ".alert", text: /Needs the Alcohol License badge/
    assert_equal @cashier, signup.reload.signup_position

    delete signup_sheet_roster_signup_path(@sheet, signup)
    assert signup.reload.cancelled?
  end

  test "no-show is refused before the event starts" do
    signup = place(@cashier, :student)
    sign_in person(:worker).user

    travel_to @event.start_time - 1.hour do
      patch mark_signup_sheet_roster_signup_path(@sheet, signup), params: { status: "no_show" }
    end
    assert_equal "Mark no-shows once the event has started.", flash[:alert]
    assert signup.reload.active?

    travel_to @event.start_time + 1.hour do
      patch mark_signup_sheet_roster_signup_path(@sheet, signup), params: { status: "no_show" }
    end
    assert signup.reload.no_show?
  end

  test "item sign-ups read Brought and Not brought" do
    dish = @sheet.signup_positions.create!(name: "Main dish", kind: :items, unit: "pizzas", capacity: 6)
    signup = Signup.place!(slot: slot_for(dish), person: person(:student), signed_up_by: person(:student), quantity: 2)
    sign_in person(:worker).user

    get roster_signup_sheet_path(@sheet)
    assert_select "td", text: "2 pizzas"
    assert_select "button", text: "Brought"

    patch mark_signup_sheet_roster_signup_path(@sheet, signup), params: { status: "fulfilled" }
    get roster_signup_sheet_path(@sheet)
    assert_select "td", text: "Brought"
  end

  test "a member who isn't an organizer is denied the roster and every roster action" do
    signup = place(@cashier, :student)
    sign_in person(:student2).user

    get roster_signup_sheet_path(@sheet)
    assert_redirected_to root_path
    get new_signup_sheet_roster_signup_path(@sheet)
    assert_redirected_to root_path
    get edit_signup_sheet_roster_signup_path(@sheet, signup)
    assert_redirected_to root_path

    assert_no_difference "Signup.count" do
      post signup_sheet_roster_signups_path(@sheet), params: { signup: { signup_slot_id: slot_for(@cashier).id, person_id: person(:student2).id } }
    end
    patch signup_sheet_roster_signup_path(@sheet, signup), params: { signup: { note: "Mine" } }
    patch mark_signup_sheet_roster_signup_path(@sheet, signup), params: { status: "fulfilled" }
    patch move_signup_sheet_roster_signup_path(@sheet, signup), params: { signup: { signup_slot_id: slot_for(@bar).id } }
    delete signup_sheet_roster_signup_path(@sheet, signup)

    signup.reload
    assert signup.active?
    assert_nil signup.note
    assert_equal @cashier, signup.signup_position
  end

  private

  def place(position, name, event: @event, **details)
    Signup.place!(slot: slot_for(position, event), person: person(name), signed_up_by: person(:admin), **details)
  end

  def relate_to_worker(name)
    Relationship.create!(parent: person(:worker), child: person(name), relationship_type: @parent_of, created_by: person(:admin))
  end
end
