require "test_helper"

class TeamTypesControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    host! "localhost"

    @admin_user = User.create!(email: "admin@example.com", password: "Password1!", admin: true)
    Person.create!(user: @admin_user, first_name: "Ada", last_name: "Admin")

    @member_user = User.create!(email: "member@example.com", password: "Password1!")
    Person.create!(user: @member_user, first_name: "Sam", last_name: "Student")
  end

  test "a member cannot create a team type" do
    sign_in @member_user

    post team_types_path, params: { team_type: { name: "Club", icon: "users" } }

    assert_not TeamType.exists?(name: "Club"), "a member created a team type"
    assert_redirected_to root_path
  end

  test "an admin can create a team type" do
    sign_in @admin_user

    post team_types_path, params: { team_type: { name: "Club", icon: "users" } }

    assert_redirected_to team_type_path(TeamType.find_by!(name: "Club"))
  end
end
