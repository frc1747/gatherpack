require "test_helper"

class SearchFormRequiredMarkerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    host! "localhost"
    @user = User.create!(email: "admin@example.com", password: "Password1!", admin: true)
    Person.create!(user: @user, first_name: "Ada", last_name: "Admin")
    sign_in @user
  end

  test "search forms do not mark inputs as required" do
    get events_path

    assert_select "form#event_search input.form-control"
    assert_select "form#event_search abbr[title=required]", count: 0
    assert_select "form#event_search .required", count: 0
  end

  test "create forms still mark required inputs" do
    get new_event_path

    assert_select "form.simple_form .required abbr[title=required]"
  end
end
