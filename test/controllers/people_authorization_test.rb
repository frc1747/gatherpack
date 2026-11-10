require "test_helper"

class PeopleAuthorizationTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    # Match the host the app generates URLs for, so legitimate success
    # redirects aren't misread as open redirects by the test harness.
    host! "localhost"

    @team = Team.create!(name: "Den A", team_type: team_types(:one))

    # Two ordinary, non-manager members of the same team.
    @attacker = create_member("joe@example.com", "Joe", "Student", manager: false)
    @victim   = create_member("sally@example.com", "Sally", "Student", manager: false)

    sign_in @attacker.user
  end

  test "a non-manager cannot impersonate another member" do
    post impersonate_person_path(@victim)

    # The session must not have been swapped to the victim's user. Pretender
    # stores the impersonated id under this key; it must stay unset.
    assert_nil session[:impersonated_user_id],
      "non-manager was able to impersonate another member"
  end

  test "a non-manager cannot delete another member" do
    assert_no_difference -> { Person.count } do
      delete person_path(@victim)
    end
    assert Person.exists?(@victim.id), "victim record was deleted"
  end

  test "a non-manager cannot edit another member's profile" do
    patch person_path(@victim), params: { person: { phone_number: "555-9999" } }

    assert_not_equal "555-9999", @victim.reload.phone_number,
      "non-manager was able to edit another member's profile"
  end

  test "a non-manager cannot grant themselves teams via mass assignment" do
    locked_team = Team.create!(name: "Admins Only", team_type: team_types(:one))

    patch person_path(@attacker), params: { person: { team_ids: [ locked_team.id ] } }

    assert_not_includes @attacker.reload.teams, locked_team,
      "non-manager granted themselves a team via mass assignment"
  end

  test "a non-admin cannot create a person" do
    assert_no_difference -> { Person.count } do
      post people_path, params: { person: { first_name: "New", last_name: "Scout" } }
    end
    assert_redirected_to root_path
  end

  test "a non-admin cannot create a person with a login" do
    post people_path, params: { person: { first_name: "Made", last_name: "Up", email: "made-up@example.com" } }

    assert_not User.exists?(email: "made-up@example.com"),
      "a non-admin created a new person and a login (password shown in the flash)"
  end

  test "a non-admin is not offered the new person form" do
    get new_person_path
    assert_redirected_to root_path

    get people_path
    assert_select "a[href=?]", new_person_path, count: 0
  end

  test "an admin can create a person with a login" do
    admin = create_member("admin@example.com", "Ada", "Admin", manager: false)
    admin.user.update!(admin: true)
    sign_in admin.user

    get people_path
    assert_select "a[href=?]", new_person_path, count: 1

    assert_difference -> { Person.count }, 1 do
      post people_path, params: { person: { first_name: "Made", last_name: "Up", email: "made-up@example.com" } }
    end
    created = Person.find_by!(first_name: "Made", last_name: "Up")
    assert_redirected_to person_path(created)
    assert_equal "made-up@example.com", created.user.email
  end

  test "a manager can add a managed member to a team they manage" do
    manager = create_member("mgr@example.com", "Mary", "Leader", manager: true)
    sign_in manager.user
    managed_team = Team.create!(name: "Den A Patrol", team_type: team_types(:one), parent: @team)

    patch person_path(@victim), params: { person: { team_ids: [ @team.id, managed_team.id ] } }

    assert_includes @victim.reload.teams, managed_team
  end

  test "a manager cannot add a managed member to a team they don't manage" do
    manager = create_member("mgr@example.com", "Mary", "Leader", manager: true)
    sign_in manager.user
    locked_team = Team.create!(name: "Admins Only", team_type: team_types(:one))

    patch person_path(@victim), params: { person: { team_ids: [ @team.id, locked_team.id ] } }

    assert_not_includes @victim.reload.teams, locked_team,
      "manager added a member to a team they don't manage"
  end

  test "a manager cannot add themselves to a team they don't manage" do
    manager = create_member("mgr@example.com", "Mary", "Leader", manager: true)
    sign_in manager.user
    locked_team = Team.create!(name: "Admins Only", team_type: team_types(:one))

    patch person_path(manager), params: { person: { team_ids: [ @team.id, locked_team.id ] } }

    assert_not_includes manager.reload.teams, locked_team,
      "manager granted themselves a team they don't manage"
  end

  test "a manager cannot remove a managed member from a team they don't manage" do
    manager = create_member("mgr@example.com", "Mary", "Leader", manager: true)
    sign_in manager.user
    other_team = Team.create!(name: "Den B", team_type: team_types(:one))
    Membership.create!(person: @victim, team: other_team)

    patch person_path(@victim), params: { person: { team_ids: [ @team.id ] } }

    assert_includes @victim.reload.teams, other_team,
      "manager removed a member from a team they don't manage"
  end

  test "a manager gives a managed member a manager-or-self badge, but not an admin-or-self one" do
    manager = create_member("mgr@example.com", "Mary", "Leader", manager: true)
    sign_in manager.user
    first_aid = Badge.create!(name: "First Aid", color: "#000000", short: "B", badge_type: badge_types(:one), permission: :added_by_manager_or_self)
    volunteer = Badge.create!(name: "Volunteer", color: "#000000", short: "B", badge_type: badge_types(:one), permission: :added_by_admin_or_self)

    patch person_path(@victim), params: { person: { badge_ids: [ first_aid.id, volunteer.id ] } }

    assert_equal [ first_aid ], @victim.reload.badges.to_a
  end

  test "a manager cannot re-link a managed member's user account" do
    manager = create_member("mgr@example.com", "Mary", "Leader", manager: true)
    sign_in manager.user
    original_user = @victim.user

    patch person_path(@victim), params: { person: { user_id: manager.user.id } }

    assert_equal original_user, @victim.reload.user,
      "manager re-linked a member's user account"
  end

  test "a sub-team manager cannot edit the profile of the parent team's manager" do
    pack = Team.create!(name: "Pack", team_type: team_types(:one))
    @team.update!(parent: pack)
    den_leader = create_member("den-leader@example.com", "Dana", "Leader", manager: true)
    pack_leader = create_member("pack-leader@example.com", "PackLeader", "Leader", manager: false)
    Membership.find_by!(person: pack_leader).update!(team: pack, manager: true)
    sign_in den_leader.user

    patch person_path(pack_leader), params: { person: { first_name: "Renamed", bio: "set by a den leader" } }

    assert_equal "PackLeader", pack_leader.reload.first_name, "the Den A manager edited the profile of the Pack manager above them"
    get person_path(pack_leader)
    assert_select "a[href=?]", edit_person_path(pack_leader), count: 0
  end

  test "a manager cannot edit the profile of an admin on their team" do
    manager = create_member("mgr@example.com", "Mary", "Leader", manager: true)
    admin = create_member("admin@example.com", "Ada", "Admin", manager: false)
    admin.user.update!(admin: true)
    sign_in manager.user

    patch person_path(admin), params: { person: { first_name: "Renamed" } }

    assert_equal "Ada", admin.reload.first_name
  end

  test "a manager can edit the profiles of members of their team and the teams below it" do
    manager = create_member("mgr@example.com", "Mary", "Leader", manager: true)
    patrol = Team.create!(name: "Patrol", team_type: team_types(:one), parent: @team)
    scout = create_member("scout@example.com", "Sam", "Scout", manager: false)
    Membership.find_by!(person: scout).update!(team: patrol)
    sign_in manager.user

    get person_path(@victim)
    assert_select "a[href=?]", edit_person_path(@victim), count: 1

    patch person_path(@victim), params: { person: { first_name: "Sal" } }
    patch person_path(scout), params: { person: { first_name: "Sammy" } }

    assert_equal "Sal", @victim.reload.first_name
    assert_equal "Sammy", scout.reload.first_name
  end

  test "co-managers of a team can edit each other's profiles" do
    manager = create_member("mgr@example.com", "Mary", "Leader", manager: true)
    co_manager = create_member("co-mgr@example.com", "Cody", "Leader", manager: true)
    sign_in manager.user

    patch person_path(co_manager), params: { person: { first_name: "Coda" } }

    assert_equal "Coda", co_manager.reload.first_name
  end

  private

  def create_member(email, first, last, manager:)
    user = User.create!(email: email, password: "Password1!")
    person = Person.create!(user: user, first_name: first, last_name: last)
    Membership.create!(person: person, team: @team, manager: manager)
    person
  end
end
