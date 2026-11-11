require "test_helper"

class PeopleSearchFormTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    host! "localhost"
    admin = User.create!(email: "admin@example.com", password: "Password1!", admin: true)
    Person.create!(user: admin, first_name: "Ada", last_name: "Admin")
    sign_in admin
  end

  test "search form is collapsed behind a button below md" do
    get people_path

    assert_response :success
    assert_select "button.d-md-none[data-bs-toggle=collapse][data-bs-target='.people-search'][aria-expanded=false]", text: /Search/
    assert_select "#people-search.collapse.d-md-block:not(.show)" do
      assert_select "input[name='q[phone_number_i_cont]']"
    end
    assert_select "#people-search-actions.collapse.d-md-inline:not(.show) input[type=submit]"
    assert_select ".people-search a", text: "New Person", count: 0
    assert_select ".card-footer > a", text: "New Person"
  end

  test "search form starts open when the page was loaded with search params" do
    get people_path, params: { q: { display_name_i_cont: "Ada" } }

    assert_response :success
    assert_select "button.d-md-none[aria-expanded=true]"
    assert_select "#people-search.collapse.show"
    assert_select "#people-search-actions.collapse.show"
  end
end
