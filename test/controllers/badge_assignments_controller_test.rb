require "test_helper"

class BadgeAssignmentsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    host! "localhost"
    @team = Team.create!(name: "Den A", team_type: team_types(:one))
    @admin = create_person("admin", admin: true)
    @member = create_person("member", team: @team)
    @volunteer = create_badge("Volunteer", :added_by_admin_or_self)
    @recognition = create_badge("Recognition", :added_by_admin)
  end

  test "a member can't move their own assignment onto an admin-only badge" do
    sign_in @member.user
    post badge_badge_assignments_path(@volunteer), params: { badge_assignment: { person_id: @member.id } }
    assignment = BadgeAssignment.find_by!(badge: @volunteer, person: @member)

    patch badge_badge_assignment_path(@volunteer, assignment), params: { badge_assignment: { badge_id: @recognition.id } }

    assert_not BadgeAssignment.exists?(badge: @recognition, person: @member),
      "member moved their self-assigned assignment onto the admin-only badge '#{@recognition.name}'"
    assert_equal @volunteer, assignment.reload.badge
  end

  test "an assignment is only found under its own badge" do
    assignment = BadgeAssignment.create!(badge: @recognition, person: @member)
    sign_in @admin.user

    get badge_badge_assignment_path(@volunteer, assignment)

    assert_response :not_found
  end

  test "an admin can still move an assignment to someone else" do
    other = create_person("other", team: @team)
    assignment = BadgeAssignment.create!(badge: @volunteer, person: @member)
    sign_in @admin.user

    patch badge_badge_assignment_path(@volunteer, assignment), params: { badge_assignment: { person_id: other.id } }

    assert_equal other, assignment.reload.person
    assert_equal @volunteer, assignment.badge
  end

  private

  def create_person(name, team: nil, manager: false, admin: false)
    user = User.create!(email: "#{name}@example.com", password: "Password1!", admin: admin)
    person = Person.create!(user: user, first_name: name.titleize, last_name: "Test")
    Membership.create!(person: person, team: team, manager: manager) if team
    person
  end

  def create_badge(name, permission, team: nil)
    Badge.create!(name: name, color: "#000000", short: "B", badge_type: badge_types(:one), team: team, permission: permission)
  end
end
