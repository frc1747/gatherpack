require "test_helper"

class VersionDisplayTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    host! "localhost"
    ENV["GATHERPACK_VERSION"] = "v1.2.3"
    ENV["GATHERPACK_REVISION"] = "34087a3f0e1c2d3b4a5968778695a4b3c2d1e0f9"
  end

  teardown do
    ENV.delete("GATHERPACK_VERSION")
    ENV.delete("GATHERPACK_REVISION")
  end

  test "the sidebar shows the version with the commit as a tooltip" do
    user = User.create!(email: "viewer@example.com", password: "Password1!")
    Person.create!(user: user, first_name: "Test", last_name: "Person")
    sign_in user

    get root_path

    assert_select "footer.footer-ad .app-version[title=?]", "34087a3", text: "1.2.3"
  end

  test "the sidebar shows nothing extra when the version is unset" do
    ENV.delete("GATHERPACK_VERSION")
    user = User.create!(email: "viewer@example.com", password: "Password1!")
    Person.create!(user: user, first_name: "Test", last_name: "Person")
    sign_in user

    get root_path

    assert_select "footer.footer-ad"
    assert_select ".app-version", count: 0
  end

  test "the sign-in page doesn't show the version" do
    get new_user_session_path

    assert_response :success
    assert_select ".app-version", count: 0
    assert_no_match "1.2.3", response.body
  end
end
