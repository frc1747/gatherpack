require "test_helper"
require_relative "../support/signups_world"

# Whose list a sign-up lands in, and what Cancel asks. worker runs the sheet;
# parent can sign up student from the member dialog.
class SignupPlacementsTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include SignupsWorld

  setup do
    host! "localhost"
    travel_to Time.zone.parse("2026-10-01 12:00")
    build_signups_world
    @restore_settings = apply_settings(signups_organizers: "Sheet Organizer > Club")
    @sheet = create_world_sheet(created_by: person(:worker), others_relationship_type_ids: [ @parent_of.id ])
    @cashier = @sheet.signup_positions.create!(name: "Cashier", capacity: 4)
    @slot = slot_for(@cashier)
  end

  teardown do
    @restore_settings&.call
  end

  test "a roster placement is recorded as placed by an organizer" do
    signup = place_from_roster(:student)

    assert signup.placed_by_organizer?
    assert_equal person(:worker), signup.signed_up_by
  end

  test "the member dialog never records a placement, even for an organizer or when asked" do
    sign_in person(:worker).user
    post signup_sheet_signups_path(@sheet), params: { signup: { signup_slot_id: @slot.id, placed_by_organizer: "1" } }

    assert_not Signup.find_by!(person: person(:worker)).placed_by_organizer?
  end

  test "a roster placement leaves the organizer's list and stays on the student's and the roster" do
    signup = place_from_roster(:student)

    get signup_sheet_path(@sheet)
    assert_response :success
    assert_select "#my_signups", count: 0

    get signup_sheets_path
    assert_select "##{ActionView::RecordIdentifier.dom_id(@sheet)}", text: /You're signed up/, count: 0

    get roster_signup_sheet_path(@sheet)
    assert_select "#roster th", text: "Signed up by"
    assert_select "##{ActionView::RecordIdentifier.dom_id(signup)} td", text: "Worker World"

    sign_out person(:worker).user
    sign_in person(:student).user
    get signup_sheet_path(@sheet)
    assert_select "#your_places ##{ActionView::RecordIdentifier.dom_id(signup)}", text: /Cashier/
    assert_select "#places_for_others", count: 0
  end

  test "the roster leaves Signed up by empty when the taker made the sign-up" do
    signup = Signup.place!(slot: @slot, person: person(:student), signed_up_by: person(:student))
    sign_in person(:worker).user

    get roster_signup_sheet_path(@sheet)
    assert_select "##{ActionView::RecordIdentifier.dom_id(signup)} td", text: "Student World", count: 1
  end

  test "an organizer who places themselves still has the place" do
    signup = place_from_roster(:worker)

    get signup_sheet_path(@sheet)
    assert_select "#your_places ##{ActionView::RecordIdentifier.dom_id(signup)}"
  end

  test "a placement on the organizer's behalf stays in their list, with the taker's name" do
    place_from_roster(:student, on_behalf_of_id: person(:worker).id)

    get signup_sheet_path(@sheet)
    assert_select "#places_for_others strong", text: "Student World"
    assert_select "#places_for_others", text: /On your behalf/
  end

  test "a sign-up made before placements were recorded stays in the signer's list" do
    signup = Signup.place!(slot: @slot, person: person(:student), signed_up_by: person(:worker))
    sign_in person(:worker).user

    get signup_sheet_path(@sheet)
    assert_select "#places_for_others ##{ActionView::RecordIdentifier.dom_id(signup)}"
  end

  test "a guardian's sign-up for their child is under the places they signed others up for" do
    Membership.create!(person: person(:parent), team: @students)
    Signup.place!(slot: @slot, person: person(:parent), signed_up_by: person(:parent))
    sign_in person(:parent).user
    post signup_sheet_signups_path(@sheet), params: { signup: { signup_slot_id: @slot.id, person_id: person(:student).id } }
    signup = Signup.find_by!(person: person(:student))
    assert_not signup.placed_by_organizer?

    get signup_sheet_path(@sheet)
    assert_select "#your_places h2", text: "Your places"
    assert_select "#your_places [id^=signup_]", count: 1
    assert_select "#places_for_others h2", text: "Places you signed others up for"
    assert_select "#places_for_others [id^=signup_]", count: 1
    assert_select "#places_for_others ##{ActionView::RecordIdentifier.dom_id(signup)} strong", text: "Student World"
  end

  test "a guardian with no place of their own only gets the list of others" do
    sign_in person(:parent).user
    post signup_sheet_signups_path(@sheet), params: { signup: { signup_slot_id: @slot.id, person_id: person(:student).id } }

    get signup_sheet_path(@sheet)
    assert_select "#your_places", count: 0
    assert_select "#places_for_others"
  end

  test "someone who takes a place for the viewer is named on the viewer's own list" do
    @sheet.on_behalf_of_anyone!
    Signup.place!(slot: @slot, person: person(:student), signed_up_by: person(:student), on_behalf_of: person(:student2))
    sign_in person(:student2).user

    get signup_sheet_path(@sheet)
    assert_select "#your_places", text: /Taken for you by Student World/
    assert_select "#places_for_others", count: 0
  end

  test "the member list's Cancel names the taker, without claiming they'll be told" do
    Membership.create!(person: person(:parent), team: @students)
    Signup.place!(slot: @slot, person: person(:parent), signed_up_by: person(:parent))
    Signup.place!(slot: @slot, person: person(:student), signed_up_by: person(:parent))
    sign_in person(:parent).user

    get signup_sheet_path(@sheet)
    assert_select "#your_places button[data-turbo-confirm=?]", "Cancel this sign-up?", text: "Cancel"
    assert_select "#places_for_others button[data-turbo-confirm=?]", "Cancel Student's place in Cashier, Snack Stand?", text: "Cancel"
  end

  test "the roster's Cancel names the taker and says they'll be told, as they are" do
    signup = place_from_roster(:student)

    get roster_signup_sheet_path(@sheet)
    assert_select "##{ActionView::RecordIdentifier.dom_id(signup)} button[data-turbo-confirm=?]",
      "Cancel Student's place in Cashier, Snack Stand? They'll be told.", text: "Cancel"
  end

  test "the roster's Cancel doesn't claim to tell a taker with no email address" do
    taker = Person.create!(first_name: "Noemail", last_name: "World")
    Membership.create!(person: taker, team: @students)
    signup = Signup.place!(slot: @slot, person: taker, signed_up_by: person(:worker), placed_by_organizer: true)
    sign_in person(:worker).user

    get roster_signup_sheet_path(@sheet)
    assert_select "##{ActionView::RecordIdentifier.dom_id(signup)} button[data-turbo-confirm=?]",
      "Cancel Noemail's place in Cashier, Snack Stand?", text: "Cancel"
  end

  test "an organizer's own place keeps the plain question on the roster" do
    signup = place_from_roster(:worker)

    get roster_signup_sheet_path(@sheet)
    assert_select "##{ActionView::RecordIdentifier.dom_id(signup)} button[data-turbo-confirm=?]", "Cancel this sign-up?", text: "Cancel"
  end

  private

  # Signs worker in and places the person through the roster's form.
  def place_from_roster(name, **params)
    sign_in person(:worker).user
    assert_difference "Signup.count" do
      post signup_sheet_roster_signups_path(@sheet), params: { signup: { signup_slot_id: @slot.id, person_id: person(name).id, **params } }
    end
    Signup.find_by!(person: person(name))
  end
end
