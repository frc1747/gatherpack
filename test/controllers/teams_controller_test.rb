require "test_helper"

class TeamsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    host! "localhost"

    @team = Team.create!(name: "Open Den", team_type: team_types(:one), join_permission: "has_account")
    @team.questions.create!(person: people(:one), title: "Who is bringing snacks?", content: "Asking for a friend.")
  end

  test "a non-member sees the public page of a team with questions enabled" do
    assert GatherPack::Features.enabled?(:qa), "this test needs the Q&A feature on (its default)"
    sign_in create_person("visitor@example.com").user

    get team_path(@team)

    assert_response :success
    assert_select "h1", text: /Open Den/
    assert_select "a[href=?]", team_memberships_path(@team), count: 0
  end

  test "a member sees the full page with its recent questions" do
    member = create_person("member@example.com")
    Membership.create!(person: member, team: @team)
    sign_in member.user

    get team_path(@team)

    assert_response :success
    assert_select "a[href=?]", team_memberships_path(@team)
    assert_match "Who is bringing snacks?", response.body
  end

  test "a manager can't add someone from outside their teams through the team form" do
    build_pack
    @den_a.update!(join_permission: :added_by_manager)
    architect = create_person("architect@example.com", admin: true, architect: true)
    Membership.create!(person: architect, team: @org)
    sign_in @den_leader.user

    patch team_path(@den_a), params: { team: { person_ids: @den_a.person_ids + [ architect.id ] } }

    assert_not Membership.exists?(person: architect, team: @den_a), "the Den A manager added the architect to Den A via person_ids"
  end

  test "a manager can't remove people from their team through the team form" do
    build_pack
    @den_a.update!(join_permission: :added_by_manager)
    admin = create_person("admin@example.com", admin: true)
    Membership.create!(person: admin, team: @den_a)
    sign_in @den_leader.user

    patch team_path(@den_a), params: { team: { name: "Den A", person_ids: [ @den_leader.id ] } }

    assert Membership.exists?(person: admin, team: @den_a)
  end

  test "a manager can't create a sub-team with someone from outside their teams in it" do
    build_pack
    outsider = create_person("outsider@example.com")
    Membership.create!(person: outsider, team: @other_org)
    sign_in @den_leader.user

    post teams_path, params: { team: { name: "Sub", parent_id: @den_a.id, team_type_id: team_types(:one).id, join_permission: "added_by_manager", person_ids: [ outsider.id ] } }

    assert_not Membership.exists?(person: outsider, team: Team.where(name: "Sub")),
      "the Den A manager created a sub-team of Den A containing an outsider"
  end

  test "an admin can set a team's people through the team form" do
    build_pack
    admin = create_person("admin@example.com", admin: true)
    outsider = create_person("outsider@example.com")
    sign_in admin.user

    patch team_path(@den_a), params: { team: { person_ids: [ outsider.id ] } }

    assert_equal [ outsider ], @den_a.reload.people.to_a
  end

  private

  test "a hostile team color can't restyle the team list or the public page" do
    @team.update!(color: "#ff0000;position:fixed;inset:0;z-index:2000;opacity:0")
    @team.announcements.create!(title: "Campout", content: "Pack tonight.", start_time: 1.hour.ago, end_time: 1.day.from_now)
    member = create_person("member@example.com")
    Membership.create!(person: member, team: @team)
    sign_in member.user

    get teams_path
    assert_response :success
    assert_includes response.body, "Open Den"
    assert_not response.body.include?("position:fixed"), "the team color injects CSS into the team list"
    sign_out :user

    sign_in create_person("visitor@example.com").user
    get team_path(@team)
    assert_response :success
    assert_includes response.body, "Campout"
    assert_not response.body.include?("position:fixed"), "the team color injects CSS into the public team page"
  end

  def create_person(email, admin: false, architect: false)
    user = User.create!(email: email, password: "Password1!", admin: admin, architect: architect)
    Person.create!(user: user, first_name: "Test", last_name: "Person")
  end

  #   Org > Pack (@pack_leader) > Den A (@den_leader, @scout)
  #   Other Org
  def build_pack
    @org = Team.create!(name: "Org", team_type: team_types(:one))
    @pack = Team.create!(name: "Pack", team_type: team_types(:one), parent: @org)
    @den_a = Team.create!(name: "Den A", team_type: team_types(:one), parent: @pack)
    @other_org = Team.create!(name: "Other Org", team_type: team_types(:one))
    @pack_leader = create_person("pack-leader@example.com")
    Membership.create!(person: @pack_leader, team: @pack, manager: true)
    @den_leader = create_person("den-leader@example.com")
    Membership.create!(person: @den_leader, team: @den_a, manager: true)
    @scout = create_person("scout@example.com")
    Membership.create!(person: @scout, team: @den_a)
  end
end
