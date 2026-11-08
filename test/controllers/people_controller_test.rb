require "test_helper"

class PeopleControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    host! "localhost"

    @shared = Team.create!(name: "Shared Den", team_type: team_types(:one), join_permission: "has_account")
    @closed = Team.create!(name: "Secret Lair", team_type: team_types(:one), join_permission: "added_by_admin")
    @viewer = create_person("viewer@example.com", "Vera")
    @member = create_person("member@example.com", "Milo")
    Membership.create!(person: @viewer, team: @shared)
    Membership.create!(person: @member, team: @shared)
    Membership.create!(person: @member, team: @closed)
  end

  test "a member sees the closed teams of another member's profile" do
    sign_in @viewer.user

    get person_path(@member)

    assert_response :success
    assert_select "a[href=?]", team_path(@shared)
    assert_match "Secret Lair", response.body
  end

  test "a closed team the viewer isn't in is an unlinked badge" do
    sign_in @viewer.user

    get person_path(@member)

    assert_response :success
    assert_match "Secret Lair", response.body
    assert_select "a[href=?]", team_path(@closed), count: 0
    assert_select "a[href=?]", team_path(@shared), count: 1
  end

  test "team discovery still leaves out closed teams the viewer isn't in" do
    sign_in @viewer.user

    get teams_path(filter: "all")

    assert_response :success
    assert_match "Shared Den", response.body
    assert_no_match "Secret Lair", response.body

    get search_path(q: "Secret", scope: "teams")

    assert_response :success
    assert_no_match "Secret Lair", response.body
  end

  test "an admin sees the closed teams on a profile" do
    admin = create_person("admin@example.com", "Ada")
    admin.user.update!(admin: true)
    sign_in admin.user

    get person_path(@member)

    assert_response :success
    assert_select "a[href=?]", team_path(@shared)
    assert_select "a[href=?]", team_path(@closed), text: /Secret Lair/
  end

  private

  def create_person(email, first_name)
    user = User.create!(email: email, password: "Password1!")
    Person.create!(user: user, first_name: first_name, last_name: "Person")
  end
end
