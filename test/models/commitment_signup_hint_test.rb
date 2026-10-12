require "test_helper"
require_relative "../support/signup_credit_world"

# The hint next to each on-behalf-of choice in the sign up dialog when a
# sign-up to the slot counts toward a commitment (spec §4.6, last paragraph).
class CommitmentSignupHintTest < ActiveSupport::TestCase
  include SignupCreditWorld

  setup do
    travel_to Time.zone.parse("2026-10-05 12:00")
    build_signup_credit_world
    @commitment = create_world_commitment
    @commitment.commitment_sources.create!(kind: "signups", subject: @sheet)
    @game = add_sheet_event("Game", "2026-10-10 10:00")
  end

  def hint(name, viewer: name, slot: slot_at(@cashier, @game))
    with_feature { Commitments::SignupHint.call(@sheet, person(name), viewer && person(viewer), slot) }
  end

  def slot_at(position, event)
    position.signup_slots.find_by!(event: event)
  end

  test "shows what the person has left on each commitment the slot counts toward" do
    assert_equal "2 shifts left on Shifts", hint(:member)

    sign_up(:member, @cashier, @game, status: :fulfilled)
    assert_equal "1 shifts left on Shifts", hint(:member)
  end

  test "joins the commitments fed through the sheet or the slot's position, leaving out other positions'" do
    other = create_world_commitment("Snacks", base_amount: 3, unit: "dishes")
    other.commitment_sources.create!(kind: "signup_positions", subject: @dish)

    assert_equal "2 shifts left on Shifts; 3 dishes left on Snacks", hint(:member, slot: slot_at(@dish, @game))
    assert_equal "2 shifts left on Shifts", hint(:member, slot: slot_at(@cashier, @game))
  end

  test "nothing for commitments whose period or team doesn't cover the slot's event" do
    december = add_sheet_event("December game", "2026-12-05 10:00")
    elsewhere = add_sheet_event("Away game", "2026-10-12 10:00", team: @other_org)

    assert_nil hint(:member, slot: slot_at(@cashier, december))
    assert_nil hint(:member, slot: slot_at(@cashier, elsewhere))
    assert_equal "2 shifts left on Shifts", hint(:member, slot: slot_at(@cashier, add_sheet_event("Members game", "2026-10-20 10:00", team: @members)))
  end

  test "nothing for people the commitment doesn't cover" do
    assert_nil hint(:outsider)
    assert_nil hint(:organizer, viewer: :admin)
  end

  test "nothing for a sheet that feeds no commitment, or with no slot" do
    other_sheet = SignupSheet.create!(title: "Raffle", team: @club, status: :open)
    other_sheet.signup_sheet_events.create!(event: @game)
    raffle = other_sheet.signup_positions.create!(name: "Seller", kind: :people)
    assert_nil with_feature { Commitments::SignupHint.call(other_sheet, person(:member), person(:member), slot_at(raffle, @game)) }

    assert_nil hint(:member, slot: nil)
  end

  test "shown only to those who may see the person's progress" do
    assert_nil hint(:member, viewer: :member2), "another member signing up on behalf of anyone"
    assert_nil hint(:member, viewer: nil)
    assert_equal "2 shifts left on Shifts", hint(:member, viewer: :admin), "an organizer of the commitment"

    @commitment.update!(group_relationship_type: @parent_of)
    assert_equal "2 shifts left on Shifts", hint(:kid, viewer: :organizer), "a parent of a group member"
  end

  test "nothing while commitments are turned off" do
    assert_nil Commitments::SignupHint.call(@sheet, person(:member), person(:member), slot_at(@cashier, @game))
  end

  test "is registered in the sign-ups hint slot" do
    Commitments::SignupViewer.set(person: person(:member), slot: slot_at(@cashier, @game)) do
      assert_equal "2 shifts left on Shifts", with_feature { Signups.extensions.on_behalf_of_hint(@sheet, person(:member)) }
    end
  end
end
