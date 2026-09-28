require "test_helper"

class MembershipsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    host! "localhost"
    @team = teams(:one)
    @other_team = teams(:two)
    @member = people(:one)
    @candidate = Person.create!(first_name: "Carol", last_name: "Carter", display_name: "Carol Carter")

    @user = users(:one)
    @user.update!(admin: true)
    sign_in @user
  end

  def candidate_id(record)
    ActionView::RecordIdentifier.dom_id(record, :candidate)
  end

  test "team candidates list people who aren't direct members" do
    get candidates_team_memberships_path(@team)

    assert_response :success
    assert_select "##{candidate_id(@candidate)}"
    assert_select "##{candidate_id(@member)}", count: 0
  end

  test "adding a person from the team page streams them into the grid" do
    assert_difference("@team.memberships.count") do
      post team_memberships_path(@team, format: :turbo_stream), params: { membership: { person_id: @candidate.id } }
    end

    assert_response :success
    assert_match "Added", response.body
    assert_match %(target="people_grid"), response.body
  end

  test "person candidates list teams they aren't on" do
    get candidates_person_memberships_path(@member)

    assert_response :success
    assert_select "##{candidate_id(@other_team)}"
    assert_select "##{candidate_id(@team)}", count: 0
  end

  test "adding a team from the person page streams it into their list" do
    assert_difference("@member.memberships.count") do
      post person_memberships_path(@member, format: :turbo_stream), params: { membership: { team_id: @other_team.id } }
    end

    assert_response :success
    assert_match %(target="memberships"), response.body
  end

  test "adding an existing member reports it on the candidate row" do
    assert_no_difference("Membership.count") do
      post team_memberships_path(@team, format: :turbo_stream), params: { membership: { person_id: @member.id } }
    end

    assert_response :unprocessable_entity
    assert_match "already a member of this team", response.body
  end

  test "the regular form still redirects" do
    post team_memberships_path(@team),
      params: { membership: { person_id: @candidate.id } },
      headers: { "Accept" => "text/vnd.turbo-stream.html, text/html, application/xhtml+xml" }

    assert_redirected_to team_memberships_path(@team)
  end

  test "people who belong only through another team say which one" do
    child = Team.create!(name: "Child Crew", team_type: team_types(:one), parent: @team)
    Membership.create!(person: @candidate, team: child)
    parent = Team.create!(name: "Parent Org", team_type: team_types(:one))
    @team.update!(parent: parent)
    boss = Person.create!(first_name: "Pat", last_name: "Parent", display_name: "Pat Parent")
    Membership.create!(person: boss, team: parent, manager: true)

    get team_memberships_path(@team)

    assert_select "##{ActionView::RecordIdentifier.dom_id(@candidate, :grid)}", text: /Via\s+Child Crew/
    assert_select "##{ActionView::RecordIdentifier.dom_id(boss, :grid)}", text: /Manager of\s+Parent Org/
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
    assert_select "input[name='people_q[display_name_cont]']"

    get team_memberships_path(@team, people_q: { display_name_cont: "Carol" })
    assert_select "#people_grid", text: /Carol Carter/
    assert_select "#people_grid", text: /Alice Anderson/, count: 0
  end

  test "a plain member cannot make themselves a manager" do
    @user.update!(admin: false)

    post team_memberships_path(@team), params: { membership: { person_id: @member.id, manager: true } }

    assert_redirected_to root_path
    refute @team.memberships.where(person: @member, manager: true).exists?
  end

  test "team candidates require managing the team" do
    @user.update!(admin: false)

    get candidates_team_memberships_path(@team)

    assert_redirected_to root_path
  end
end
