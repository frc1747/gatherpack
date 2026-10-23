require "test_helper"
require_relative "../support/signup_credit_world"

# The commitments hint in the real sign up dialog: a parent signing up for
# their child sees what the child has left.
class SignupCreditHintTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include SignupCreditWorld

  setup do
    host! "localhost"
    travel_to Time.zone.parse("2026-10-05 12:00")
    build_signup_credit_world
    @sheet.update!(others_relationship_type_ids: [ @parent_of.id ], on_behalf_of_mode: :related_people)
    @game = add_sheet_event("Game", "2026-10-10 10:00")
    @commitment = create_world_commitment(group_relationship_type: @parent_of)
    @commitment.commitment_sources.create!(kind: "signups", subject: @sheet)
  end

  test "the on-behalf-of choices show what each person owing has left" do
    sign_in person(:organizer).user

    with_settings(feature_commitments: "true", feature_signups: "true") do
      get new_signup_sheet_signup_path(@sheet, slot_id: @cashier.signup_slots.find_by!(event: @game).id)
    end

    assert_response :success
    assert_select "label", text: "Kid World (2 shifts left on Shifts)"
    assert_select "label", text: "Organizer World"
  end

  test "editing a sign-up shows the hints for its slot" do
    signup = sign_up(:organizer, @cashier, @game, on_behalf_of: :kid)
    sign_in person(:organizer).user

    with_settings(feature_commitments: "true", feature_signups: "true") do
      get edit_signup_sheet_signup_path(@sheet, signup)
    end

    assert_response :success
    assert_select "label", text: "Kid World (2 shifts left on Shifts)"
  end
end
