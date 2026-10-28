require "test_helper"

class MembershipsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    host! "localhost"
    @team = teams(:one)
    @member = people(:one)
    @candidate = Person.create!(first_name: "Carol", last_name: "Carter", display_name: "Carol Carter")

    @user = users(:one)
    @user.update!(admin: true)
    sign_in @user
  end

  test "membership type filters" do
    child = Team.create!(name: "Child Crew", team_type: team_types(:one), parent: @team)
    Membership.create!(person: @candidate, team: child)
    Membership.create!(person: @member, team: child)
    parent = Team.create!(name: "Parent Org", team_type: team_types(:one))
    @team.update!(parent: parent)
    boss = Person.create!(first_name: "Pat", last_name: "Parent", display_name: "Pat Parent")
    Membership.create!(person: boss, team: parent, manager: true)
    in_grid = ->(person) { "##{ActionView::RecordIdentifier.dom_id(person)}" }

    get team_memberships_path(@team, member_type: "parent_manager")
    assert_select in_grid.(boss)
    assert_select in_grid.(@candidate), count: 0

    # @member is on both this team and the child team, so only @candidate counts.
    get team_memberships_path(@team, member_type: "child_member")
    assert_select in_grid.(@candidate)
    assert_select in_grid.(@member), count: 0
  end

  test "name search narrows the people grid" do
    Membership.create!(person: @candidate, team: @team)

    get team_memberships_path(@team)
    assert_select "input[name='people_q[display_name_i_cont]']"

    get team_memberships_path(@team, people_q: { display_name_i_cont: "Carol" })
    assert_select "#people_grid", text: /Carol Carter/
    assert_select "#people_grid", text: /Alice Anderson/, count: 0
  end

  test "a manager can't move their membership to another team" do
    build_pack
    membership = Membership.find_by!(person: @den_leader, team: @den_a)
    sign_in @den_leader.user

    patch team_membership_path(@den_a, membership), params: { membership: { team_id: @org.id, manager: "1" } }

    assert_not Membership.exists?(person: @den_leader, team: @org),
      "the Den A manager moved their membership to the root team as its manager"
    assert_equal @den_a, membership.reload.team
  end

  test "a manager can't move a member into a team they don't manage" do
    build_pack
    membership = Membership.find_by!(person: @scout, team: @den_a)
    sign_in @den_leader.user

    patch team_membership_path(@den_a, membership), params: { membership: { team_id: @other_org.id } }

    assert_not Membership.exists?(person: @scout, team: @other_org), "the Den A manager moved a member into another org"
  end

  test "editing a membership doesn't change whose it is" do
    build_pack
    membership = Membership.find_by!(person: @scout, team: @den_a)
    sign_in @den_leader.user

    patch team_membership_path(@den_a, membership), params: { membership: { person_id: @pack_leader.id, manager: "1" } }

    assert_equal @scout, membership.reload.person, "the Den A manager handed a member's membership to someone else"
  end

  test "a manager can make a member they manage a manager of their team" do
    build_pack
    membership = Membership.find_by!(person: @scout, team: @den_a)
    sign_in @den_leader.user

    patch team_membership_path(@den_a, membership), params: { membership: { manager: "1" } }

    assert_redirected_to team_memberships_path(@den_a)
    assert membership.reload.manager?
  end

  test "a manager can't change or remove an admin's membership in their team" do
    build_pack
    admin = create_member("den-admin", @den_a, admin: true)
    membership = Membership.find_by!(person: admin, team: @den_a)
    sign_in @den_leader.user

    patch team_membership_path(@den_a, membership), params: { membership: { manager: "1" } }
    assert_not membership.reload.manager?

    delete team_membership_path(@den_a, membership)
    assert Membership.exists?(membership.id), "the manager removed an admin from their team"
  end

  test "a manager can't demote the manager of a parent team who is also on their team" do
    build_pack
    membership = Membership.create!(person: @pack_leader, team: @den_a, manager: true)
    sign_in @den_leader.user

    patch team_membership_path(@den_a, membership), params: { membership: { manager: "0" } }

    assert membership.reload.manager?, "the Den A manager demoted the Pack manager above them"
  end

  test "a manager can leave their team" do
    build_pack
    membership = Membership.find_by!(person: @den_leader, team: @den_a)
    sign_in @den_leader.user

    delete team_membership_path(@den_a, membership)

    assert_not Membership.exists?(membership.id)
  end

  test "a manager can't add someone from outside their teams" do
    build_pack
    outsider = create_member("outsider", @other_org)
    sign_in @den_leader.user

    post team_memberships_path(@den_a), params: { membership: { person_id: outsider.id } }

    assert_not Membership.exists?(person: outsider, team: @den_a), "the Den A manager added an outsider from another org to Den A"
  end

  test "a manager can't add an outsider and then take over their login" do
    build_pack
    outsider = create_member("outsider", @other_org)
    sign_in @den_leader.user

    post team_memberships_path(@den_a), params: { membership: { person_id: outsider.id } }
    patch person_user_path(outsider), params: { user: { password: "Hijacked123!", password_confirmation: "Hijacked123!" } }

    assert_not Membership.exists?(person: outsider, team: @den_a), "the Den A manager added an outsider to Den A"
    assert_not outsider.user.reload.valid_password?("Hijacked123!")
  end

  test "a manager can't add someone to a team they don't manage from the person's page" do
    build_pack
    sign_in @den_leader.user

    post person_memberships_path(@scout), params: { membership: { team_id: @other_org.id } }

    assert_not Membership.exists?(person: @scout, team: @other_org)
  end

  test "a manager can add someone they manage to another team they manage" do
    build_pack
    patrol = Team.create!(name: "Patrol", team_type: team_types(:one), parent: @den_a)
    sign_in @den_leader.user

    post team_memberships_path(patrol), params: { membership: { person_id: @scout.id } }
    assert Membership.exists?(person: @scout, team: patrol)

    delete team_membership_path(patrol, Membership.find_by!(person: @scout, team: patrol))
    post person_memberships_path(@scout), params: { membership: { team_id: patrol.id } }
    assert Membership.exists?(person: @scout, team: patrol)
  end

  test "a member can join an open team themselves" do
    build_pack
    open_team = Team.create!(name: "Open", team_type: team_types(:one), join_permission: :has_account)
    sign_in @scout.user

    post team_memberships_path(open_team), params: { membership: { person_id: @scout.id, manager: false } }

    assert Membership.exists?(person: @scout, team: open_team, manager: false)
  end

  test "an outsider can't list the roster of a team that requires approval" do
    build_pack
    @den_a.update!(join_permission: :requires_approval)
    outsider = create_member("outsider", @other_org)
    sign_in outsider.user

    get team_memberships_path(@den_a)

    assert_redirected_to root_path
    assert_select "#people_grid", count: 0
  end

  test "a team's other pages offer the Members tab only to those who may list the roster" do
    build_pack
    @den_a.update!(join_permission: :requires_approval)
    outsider = create_member("outsider", @other_org)

    sign_in outsider.user
    get events_team_path(@den_a)
    assert_response :success
    assert_select "a[href='#{team_memberships_path(@den_a)}']", count: 0

    sign_in @scout.user
    get events_team_path(@den_a)
    assert_select "a[href='#{team_memberships_path(@den_a)}']", text: "Members"
  end

  test "an outsider can't list the roster of a team anyone may join" do
    build_pack
    @den_a.update!(join_permission: :has_account)
    outsider = create_member("outsider", @other_org)
    sign_in outsider.user

    get team_memberships_path(@den_a)

    assert_redirected_to root_path
  end

  test "a member of a sub-team can't list the roster of the team above it" do
    build_pack
    sign_in @scout.user

    get team_memberships_path(@pack)

    assert_redirected_to root_path
  end

  test "members, managers, managers of a parent team and admins list the roster" do
    build_pack
    @den_a.update!(join_permission: :requires_approval)
    admin = create_member("admin", @other_org, admin: true)

    [ @scout, @den_leader, @pack_leader, admin ].each do |viewer|
      sign_in viewer.user

      get team_memberships_path(@den_a)

      assert_response :success, "#{viewer.first_name} couldn't list the roster"
      assert_select "#people_grid", text: /Scout Test/
    end
  end

  test "an outsider can't list the teams of someone they can't see" do
    build_pack
    outsider = create_member("outsider", @other_org)
    sign_in outsider.user

    get person_memberships_path(@scout)

    assert_response :not_found
  end

  private

  #   Org > Pack (@pack_leader) > Den A (@den_leader, @scout)
  #   Other Org
  def build_pack
    @org = Team.create!(name: "Org", team_type: team_types(:one))
    @pack = Team.create!(name: "Pack", team_type: team_types(:one), parent: @org)
    @den_a = Team.create!(name: "Den A", team_type: team_types(:one), parent: @pack)
    @other_org = Team.create!(name: "Other Org", team_type: team_types(:one))
    @pack_leader = create_member("pack-leader", @pack, manager: true)
    @den_leader = create_member("den-leader", @den_a, manager: true)
    @scout = create_member("scout", @den_a)
  end

  def create_member(name, team, manager: false, admin: false)
    user = User.create!(email: "#{name}@example.com", password: "Password1!", admin: admin)
    person = Person.create!(user: user, first_name: name.titleize, last_name: "Test")
    Membership.create!(person: person, team: team, manager: manager)
    person
  end
end
