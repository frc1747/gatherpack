require "test_helper"
require_relative "../support/signups_world"

class SignupPolicyTest < ActiveSupport::TestCase
  include SignupsWorld

  setup do
    build_signups_world
    @sheet = create_world_sheet(others_relationship_type_ids: [ @parent_of.id ])
    @position = @sheet.signup_positions.create!(name: "Cashier")
    # The parent is an organizer too.
    Membership.create!(person: person(:parent), team: @concessions)
    BadgeAssignment.create!(badge: @organizer_badge, person: person(:parent))
    with_organizer_grants("Sheet Organizer > Club") do
      @sheet.signup_sheet_organizers.create!(person: person(:worker))
      @sheet.signup_sheet_organizers.create!(person: person(:parent))
    end
    @signup = Signup.place!(slot: slot_for(@position), person: person(:student), signed_up_by: person(:student))
  end

  test "members change and cancel their own and their family's sign-ups before the cutoff" do
    assert policy(:student, @signup).update?
    assert policy(:student, @signup).destroy?
    assert policy(:parent, @signup).destroy?
    assert_not policy(:student2, @signup).destroy?

    travel_to @event.start_time do
      assert_not policy(:student, @signup).destroy?
    end
  end

  test "organizers mark, move and override for others" do
    assert policy(:worker, @signup).place?
    assert policy(:worker, @signup).mark?
    assert policy(:worker, @signup).move?
    assert policy(:worker, @signup).override?
    assert_nil policy(:worker, @signup).self_approval_reason
    assert_not policy(:student2, @signup).mark?
  end

  test "organizers can't mark, move or override for themselves or a relative" do
    parent = policy(:parent, @signup)
    assert parent.place?, "ordinary sign-up and cancel are unaffected"
    assert_not parent.mark?
    assert_not parent.move?
    assert_not parent.override?
    assert_equal "Another organizer needs to mark your own family's sign-ups", parent.self_approval_reason

    own = Signup.place!(slot: slot_for(@position), person: person(:worker), signed_up_by: person(:worker))
    assert_not policy(:worker, own).mark?
    assert policy(:admin, own).mark?
    assert_not policy(:worker, @signup).move_to?(person(:worker))
  end

  test "on behalf of a relative counts as theirs" do
    @sheet.on_behalf_of_anyone!
    covered = Signup.place!(slot: slot_for(@position), person: person(:student2), signed_up_by: person(:student2), on_behalf_of: person(:student))

    assert_not policy(:parent, covered).mark?
  end

  private

  def policy(name, record)
    SignupPolicy.new(person(name).user, record)
  end
end
