require "test_helper"

class ShortcutsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    host! "localhost"
    @team = teams(:one)
    @manager_user = User.create!(email: "manager@example.com", password: "Password1!")
    manager = Person.create!(user: @manager_user, first_name: "Mary", last_name: "Manager")
    Membership.create!(person: manager, team: @team, manager: true)
    @valid_attributes = { name: "Attendance", icon: "list", team_id: @team.id, target: "https://example.com/attendance", color: "#3788d8" }
  end

  test "a manager can create a shortcut for their team" do
    sign_in @manager_user

    assert_difference -> { Shortcut.count }, 1 do
      post shortcuts_path, params: { shortcut: @valid_attributes }
    end
    assert_redirected_to shortcut_path(Shortcut.find_by!(name: "Attendance"))
  end

  test "a shortcut can't be created with a javascript: target or CSS in its color" do
    sign_in @manager_user

    assert_no_difference -> { Shortcut.count } do
      post shortcuts_path, params: { shortcut: @valid_attributes.merge(target: "javascript:alert(1)") }
    end
    assert_response :unprocessable_entity

    assert_no_difference -> { Shortcut.count } do
      post shortcuts_path, params: { shortcut: @valid_attributes.merge(color: "#ff0000;position:fixed;inset:0") }
    end
    assert_response :unprocessable_entity
  end

  test "the show page doesn't link a stored target that isn't a web URL" do
    shortcut = Shortcut.create!(@valid_attributes)
    shortcut.update_columns(target: "javascript:alert(1)")
    sign_in @manager_user

    get shortcut_path(shortcut)

    assert_response :success
    assert_not response.body.include?(%(href="javascript:)), "the stored javascript: target is rendered as a link"
    assert_includes response.body, "javascript:alert(1)"
  end

  test "the show page links a web target" do
    shortcut = Shortcut.create!(@valid_attributes)
    sign_in @manager_user

    get shortcut_path(shortcut)

    assert_select "a[href=?]", "https://example.com/attendance"
  end

  test "a manager cannot move a shortcut onto a team they don't manage" do
    shortcut = Shortcut.create!(@valid_attributes)
    sign_in @manager_user

    patch shortcut_path(shortcut), params: { shortcut: { team_id: teams(:two).id } }

    assert_equal @team.id, shortcut.reload.team_id, "a manager moved a shortcut onto a team they don't manage"
    assert_redirected_to root_path
  end

  test "a manager can move a shortcut between teams they manage" do
    sub_team = Team.create!(name: "Sub Team", team_type: team_types(:one), parent: @team)
    shortcut = Shortcut.create!(@valid_attributes)
    sign_in @manager_user

    patch shortcut_path(shortcut), params: { shortcut: { team_id: sub_team.id } }

    assert_redirected_to shortcut_path(shortcut)
    assert_equal sub_team.id, shortcut.reload.team_id
  end

  test "an admin can move a shortcut onto any team" do
    admin_user = User.create!(email: "admin@example.com", password: "Password1!", admin: true)
    Person.create!(user: admin_user, first_name: "Ada", last_name: "Admin")
    shortcut = Shortcut.create!(@valid_attributes)
    sign_in admin_user

    patch shortcut_path(shortcut), params: { shortcut: { team_id: teams(:two).id } }

    assert_equal teams(:two).id, shortcut.reload.team_id
  end
end
