require "test_helper"

class WelcomeControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    host! "localhost"
    @admin_user = User.create!(email: "admin@example.com", password: "Password1!", admin: true)
    Person.create!(user: @admin_user, first_name: "Ada", last_name: "Admin")
    @shortcut = Shortcut.create!(name: "Attendance", icon: "list", team: teams(:one), target: "https://example.com/attendance", color: "#3788d8")
  end

  test "the dashboard links shortcuts in their color" do
    sign_in @admin_user

    get root_path

    assert_response :success
    assert_select "a.btn-tool[href=?][style*=?]", "https://example.com/attendance", "background-color: #3788d8"
  end

  test "a stored shortcut can't run script or restyle the admin's dashboard" do
    # Rows saved before targets and colors were validated.
    @shortcut.update_columns(target: "javascript:fetch('/users')", color: "#ff0000;position:fixed;inset:0;z-index:2000;opacity:0")
    sign_in @admin_user

    get root_path

    assert_response :success
    assert_not response.body.include?(%(href="javascript:)),
      "A manager's javascript: shortcut target renders as a live link on the admin's dashboard"
    assert_not response.body.include?("position:fixed;inset:0"),
      "A manager's shortcut color injects CSS into the style attribute"
  end

  test "a hostile team color can't restyle announcements on the dashboard" do
    team = teams(:one)
    team.update!(color: "#ff0000;position:fixed;inset:0")
    team.announcements.create!(title: "Campout", content: "Pack tonight.", start_time: 1.hour.ago, end_time: 1.day.from_now)
    sign_in @admin_user

    get root_path

    assert_response :success
    assert_includes response.body, "Campout"
    assert_not response.body.include?("position:fixed"), "the team color injects CSS into the dashboard"
  end
end
