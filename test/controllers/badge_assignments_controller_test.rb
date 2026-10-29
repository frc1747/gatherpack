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

  test "a member can't give a self-assignable badge to someone else" do
    outsider = create_person("outsider", team: Team.create!(name: "Den B", team_type: team_types(:one)))
    sign_in @member.user

    post badge_badge_assignments_path(@volunteer), params: { badge_assignment: { person_id: outsider.id } }

    assert_not BadgeAssignment.exists?(badge: @volunteer, person: outsider),
      "member assigned a self-assignable badge to a member of another team"
  end

  test "a member can't remove a teammate's self-assignable badge" do
    teammate = create_person("teammate", team: @team)
    assignment = BadgeAssignment.create!(badge: @volunteer, person: teammate)
    sign_in @member.user

    delete badge_badge_assignment_path(@volunteer, assignment)

    assert BadgeAssignment.exists?(assignment.id), "member removed a teammate's badge assignment"
  end

  test "a member can't move their own assignment to someone else" do
    teammate = create_person("teammate", team: @team)
    assignment = BadgeAssignment.create!(badge: @volunteer, person: @member)
    sign_in @member.user

    patch badge_badge_assignment_path(@volunteer, assignment), params: { badge_assignment: { person_id: teammate.id } }

    assert_equal @member, assignment.reload.person
  end

  test "a member takes a self-assignable badge, sees it and gives it back" do
    sign_in @member.user

    get new_badge_badge_assignment_path(@volunteer)
    assert_response :success
    assert_match(/scope=me\b/, response.body)

    post badge_badge_assignments_path(@volunteer), params: { badge_assignment: { person_id: @member.id } }
    assignment = BadgeAssignment.find_by!(badge: @volunteer, person: @member)

    get badge_badge_assignments_path(@volunteer)
    assert_response :success
    assert_select "#badge_assignments a", text: @member.identifier_name

    get badge_badge_assignment_path(@volunteer, assignment)
    assert_select "a.btn-danger", text: "Delete"

    assert_difference -> { BadgeAssignment.count }, -1 do
      delete badge_badge_assignment_path(@volunteer, assignment)
    end
  end

  test "a member of the team takes its member badge, but not for a teammate" do
    teammate = create_person("teammate", team: @team)
    badge = create_badge("Crew", :added_by_current_member, team: @team)
    sign_in @member.user

    post badge_badge_assignments_path(badge), params: { badge_assignment: { person_id: teammate.id } }
    assert_not BadgeAssignment.exists?(badge: badge, person: teammate)

    post badge_badge_assignments_path(badge), params: { badge_assignment: { person_id: @member.id } }
    assert BadgeAssignment.exists?(badge: badge, person: @member)
  end

  test "a member may take a self-assignable badge but sees no delete button on a teammate's" do
    teammate = create_person("teammate", team: @team)
    assignment = BadgeAssignment.create!(badge: @volunteer, person: teammate)
    sign_in @member.user

    get badge_badge_assignments_path(@volunteer)
    assert_response :success
    assert_select "a", text: "New badge assignment"

    get badge_badge_assignment_path(@volunteer, assignment)
    assert_response :success
    assert_select "a", text: "Delete", count: 0
  end

  test "a member sees no assignment controls on an admin-only badge" do
    teammate = create_person("teammate", team: @team)
    assignment = BadgeAssignment.create!(badge: @recognition, person: teammate)
    sign_in @member.user

    get badge_badge_assignments_path(@recognition)
    assert_response :success
    assert_select "a", text: "New badge assignment", count: 0

    get badge_badge_assignment_path(@recognition, assignment)
    assert_response :success
    assert_select "a", text: "Delete", count: 0
  end

  test "a manager gives a manager-or-self badge without a team to the people they manage" do
    manager = create_person("manager", team: @team, manager: true)
    first_aid = create_badge("First Aid", :added_by_manager_or_self)
    sign_in manager.user

    get new_badge_badge_assignment_path(first_aid)
    assert_match(/scope=managed_people\b/, response.body)

    post badge_badge_assignments_path(first_aid), params: { badge_assignment: { person_id: @member.id } }
    assignment = BadgeAssignment.find_by!(badge: first_aid, person: @member)

    delete badge_badge_assignment_path(first_aid, assignment)
    assert_not BadgeAssignment.exists?(assignment.id)
  end

  test "a manager can't give a manager-or-self badge to someone they don't manage" do
    manager = create_person("manager", team: @team, manager: true)
    outsider = create_person("outsider", team: Team.create!(name: "Den B", team_type: team_types(:one)))
    first_aid = create_badge("First Aid", :added_by_manager_or_self)
    sign_in manager.user

    post badge_badge_assignments_path(first_aid), params: { badge_assignment: { person_id: outsider.id } }

    assert_not BadgeAssignment.exists?(badge: first_aid, person: outsider)
  end

  test "a team's manager sees and removes its badge from someone who has left the team" do
    manager = create_person("manager", team: @team, manager: true)
    badge = create_badge("Patrol Leader", :added_by_manager, team: @team)
    assignment = BadgeAssignment.create!(badge: badge, person: @member)
    @member.memberships.destroy_all
    sign_in manager.user

    get badge_badge_assignments_path(badge)
    assert_select "#badge_assignments a", text: @member.identifier_name

    delete badge_badge_assignment_path(badge, assignment)
    assert_not BadgeAssignment.exists?(assignment.id)
  end

  test "an admin-only badge is only given and taken by admins" do
    sign_in @member.user
    post badge_badge_assignments_path(@recognition), params: { badge_assignment: { person_id: @member.id } }
    assert_not BadgeAssignment.exists?(badge: @recognition, person: @member)
    sign_out :user

    sign_in @admin.user
    post badge_badge_assignments_path(@recognition), params: { badge_assignment: { person_id: @member.id } }
    assignment = BadgeAssignment.find_by!(badge: @recognition, person: @member)
    delete badge_badge_assignment_path(@recognition, assignment)
    assert_not BadgeAssignment.exists?(assignment.id)
  end

  test "a team's manager gives its badge to a member and takes it back" do
    manager = create_person("manager", team: @team, manager: true)
    badge = create_badge("Patrol Leader", :added_by_manager, team: @team)
    sign_in manager.user

    post badge_badge_assignments_path(badge), params: { badge_assignment: { person_id: @member.id } }
    assignment = BadgeAssignment.find_by!(badge: badge, person: @member)

    delete badge_badge_assignment_path(badge, assignment)
    assert_not BadgeAssignment.exists?(assignment.id)
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
