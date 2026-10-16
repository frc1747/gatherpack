require "test_helper"
require_relative "../support/signups_world"

class SignupSheetPolicyTest < ActiveSupport::TestCase
  include SignupsWorld

  setup do
    build_signups_world
    @sheet = create_world_sheet
  end

  test "create: admins, team managers, and grant holders for teams in reach" do
    with_organizer_grants("Sheet Organizer > Club") do
      assert policy(:admin, SignupSheet.new(team: @other_org)).create?
      assert policy(:concessions_manager, SignupSheet.new(team: @concessions)).create?
      assert_not policy(:concessions_manager, SignupSheet.new(team: @club)).create?
      assert policy(:worker, SignupSheet.new(team: @club)).create?
      assert_not policy(:worker, SignupSheet.new(team: @org)).create?, "above the grant's highest team"
      assert_not policy(:worker, SignupSheet.new(team: @students)).create?, "not their own team or one below it"
      assert_not policy(:student, SignupSheet.new(team: @students)).create?
      assert policy(:worker, SignupSheet).new?
      assert_not policy(:student, SignupSheet).new?
    end
  end

  test "manage: organizers only" do
    with_organizer_grants("Sheet Organizer > Club") do
      assert_not policy(:worker, @sheet).manage?
      @sheet.signup_sheet_organizers.create!(person: person(:worker))

      assert policy(:worker, @sheet).manage?
      assert policy(:worker, @sheet).roster?
      assert policy(:admin, @sheet).update?
      assert_not policy(:student, @sheet).manage?
      assert_not policy(:concessions_manager, @sheet).manage?
    end
  end

  test "show: the audience while open or closed, organizers always" do
    assert policy(:student, @sheet).show?
    assert_not policy(:outsider, @sheet).show?
    assert_not policy(:parent, @sheet).show?

    @sheet.update!(others_relationship_type_ids: [ @parent_of.id ])
    assert policy(:parent, @sheet).show?, "a parent who can sign up their child"

    @sheet.draft!
    assert_not policy(:student, @sheet).show?
    assert policy(:admin, @sheet).show?

    assert_equal [], SignupSheetPolicy::Scope.new(person(:student).user, SignupSheet).resolve.to_a
    @sheet.open!
    assert_equal [ @sheet ], SignupSheetPolicy::Scope.new(person(:student).user, SignupSheet).resolve.to_a
    assert_equal [], SignupSheetPolicy::Scope.new(person(:outsider).user, SignupSheet).resolve.to_a
  end

  test "a listed organizer loses the sheet when their badge goes" do
    with_organizer_grants("Sheet Organizer > Club") do
      @sheet.signup_sheet_organizers.create!(person: person(:worker))
      assert policy(:worker, @sheet).manage?
      assert_includes organizer_view(:worker), @sheet

      BadgeAssignment.find_by!(badge: @organizer_badge, person: person(:worker)).destroy!
      assert_not policy(:worker, @sheet).manage?
      assert_not_includes organizer_view(:worker), @sheet
    end
  end

  test "a listed organizer loses the sheet when it moves out of their reach" do
    with_organizer_grants("Sheet Organizer > Club") do
      @sheet.signup_sheet_organizers.create!(person: person(:worker))
      @sheet.update!(team: @other_org)

      assert_not policy(:worker, @sheet).manage?
      assert_not_includes organizer_view(:worker), @sheet
    end
  end

  test "a creator who managed the team loses the sheet when they stop managing it" do
    sheet = SignupSheet.create!(title: "Bake Sale", team: @concessions, created_by: person(:concessions_manager), status: :draft)
    assert policy(:concessions_manager, sheet).manage?

    Membership.find_by!(person: person(:concessions_manager), team: @concessions).update!(manager: false)
    assert_not policy(:concessions_manager, sheet).manage?
    assert_not_includes organizer_view(:concessions_manager), sheet
  end

  test "destroy only while there are no sign-ups" do
    assert policy(:admin, @sheet).destroy?

    position = @sheet.signup_positions.create!(name: "Cashier")
    Signup.place!(slot: slot_for(position), person: person(:student), signed_up_by: person(:student))
    assert_not policy(:admin, @sheet).destroy?
  end

  test "parts of a sheet are run by its organizers" do
    position = @sheet.signup_positions.create!(name: "Cashier")
    rule = position.signup_position_rules.create!(kind: :age, min_age: 18)

    assert SignupPositionPolicy.new(person(:admin).user, position).update?
    assert SignupPositionRulePolicy.new(person(:admin).user, rule).destroy?
    assert_not SignupPositionPolicy.new(person(:student).user, position).update?
    assert_not SignupSlotPolicy.new(person(:student).user, slot_for(position)).update?
    assert_not SignupSheetOrganizerPolicy.new(person(:student).user, @sheet.signup_sheet_organizers.build).create?
  end

  private

  # Drafts are only visible to organizers.
  def organizer_view(name)
    SignupSheet.where(id: @sheet.id).update_all(status: SignupSheet.statuses[:draft])
    SignupSheetPolicy::Scope.new(person(name).user, SignupSheet).resolve.to_a
  end

  def policy(name, record)
    SignupSheetPolicy.new(person(name).user, record)
  end
end
