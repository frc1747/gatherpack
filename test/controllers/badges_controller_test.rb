require "test_helper"

class BadgesControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    host! "localhost"
    @team = Team.create!(name: "Den A", team_type: team_types(:one))
    @admin = create_person("admin", admin: true)
    @manager = create_person("manager", team: @team, manager: true)
    @member = create_person("member", team: @team)
    @volunteer = Badge.create!(name: "Volunteer", color: "#000000", short: "B", badge_type: badge_types(:one), permission: :added_by_admin_or_self)
  end

  test "a member can't edit a self-assignable badge" do
    sign_in @member.user

    patch badge_path(@volunteer), params: { badge: { permission: "added_by_admin", name: "Renamed", person_ids: [ @member.id ] } }

    @volunteer.reload
    assert_equal "added_by_admin_or_self", @volunteer.permission,
      "member changed the badge's permission to #{@volunteer.permission}, " \
      "name '#{@volunteer.name}', holders #{@volunteer.people.map(&:first_name).inspect}"
    assert_equal "Volunteer", @volunteer.name
    assert_empty @volunteer.people
  end

  test "a member can't delete a self-assignable badge" do
    BadgeAssignment.create!(badge: @volunteer, person: @manager)
    sign_in @member.user

    delete badge_path(@volunteer)

    assert Badge.exists?(@volunteer.id), "member deleted the badge and every holder's assignment"
  end

  test "a member sees no edit or delete buttons on a self-assignable badge, but can take it" do
    sign_in @member.user

    get badge_path(@volunteer)

    assert_response :success
    assert_select "a", text: "Edit", count: 0
    assert_select "a", text: "Delete", count: 0
    assert_select "a[href='#{badge_badge_assignments_path(@volunteer)}']"
  end

  test "a team's manager edits the team's badge" do
    badge = Badge.create!(name: "Patrol Leader", color: "#000000", short: "B", badge_type: badge_types(:one), team: @team, permission: :added_by_manager)
    sign_in @manager.user

    patch badge_path(badge), params: { badge: { name: "Senior Patrol Leader" } }

    assert_equal "Senior Patrol Leader", badge.reload.name
  end

  test "a team's manager can't move its badge to a team they don't manage" do
    other_team = Team.create!(name: "Den B", team_type: team_types(:one))
    badge = Badge.create!(name: "Patrol Leader", color: "#000000", short: "B", badge_type: badge_types(:one), team: @team, permission: :added_by_manager)
    sign_in @manager.user

    patch badge_path(badge), params: { badge: { team_id: other_team.id } }

    assert_equal @team, badge.reload.team
  end

  test "a team's manager can't edit or delete an admin-only badge" do
    badge = Badge.create!(name: "Recognition", color: "#000000", short: "B", badge_type: badge_types(:one), team: @team, permission: :added_by_admin_or_self)
    sign_in @manager.user

    patch badge_path(badge), params: { badge: { name: "Renamed" } }
    assert_equal "Recognition", badge.reload.name

    delete badge_path(badge)
    assert Badge.exists?(badge.id)
  end

  test "a team's manager is offered only the kinds and teams they may set" do
    badge = Badge.create!(name: "Patrol Leader", color: "#000000", short: "B", badge_type: badge_types(:one), team: @team, permission: :added_by_manager)
    sign_in @manager.user

    get edit_badge_path(badge)

    assert_response :success
    assert_select "select#badge_permission option", count: BadgePolicy::MANAGED_PERMISSIONS.size
    assert_select "select#badge_permission option[value=added_by_admin]", count: 0
    assert_match(/scope=managed_teams\b/, response.body)
  end

  test "an admin is offered every kind and team" do
    sign_in @admin.user

    get edit_badge_path(@volunteer)

    assert_select "select#badge_permission option", count: Badge.permissions.size
    assert_match(/scope=teams\b/, response.body)
  end

  test "an admin edits and deletes a badge" do
    sign_in @admin.user

    patch badge_path(@volunteer), params: { badge: { name: "Helper", person_ids: [ @member.id ] } }
    assert_equal "Helper", @volunteer.reload.name
    assert_equal [ @member ], @volunteer.people.to_a

    delete badge_path(@volunteer)
    assert_not Badge.exists?(@volunteer.id)
  end

  private

  def create_person(name, team: nil, manager: false, admin: false)
    user = User.create!(email: "#{name}@example.com", password: "Password1!", admin: admin)
    person = Person.create!(user: user, first_name: name.titleize, last_name: "Test")
    Membership.create!(person: person, team: team, manager: manager) if team
    person
  end
end
