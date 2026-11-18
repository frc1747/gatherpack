require "test_helper"

class CheckinFieldsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    host! "localhost"
    admin = User.create!(email: "admin@example.com", password: "Password1!", admin: true)
    Person.create!(user: admin, first_name: "Ada", last_name: "Admin")
    sign_in admin
  end

  test "Delete says how many answers go with the field" do
    get checkin_field_url(checkin_fields(:one))
    assert_select "a[data-turbo-method=delete][data-turbo-confirm=?]", "Are you sure? This also deletes 1 check-in answer."

    checkin_field_responses(:one).update!(response: "")
    get checkin_field_url(checkin_fields(:one))
    assert_select "a[data-turbo-method=delete][data-turbo-confirm=?]", "Are you sure?"
  end

  test "admin deletes a field that has responses, and its responses go with it" do
    field = checkin_fields(:one)

    assert_difference [ "CheckinField.count", "CheckinFieldResponse.count" ], -1 do
      delete checkin_field_url(field)
    end
    assert_redirected_to checkin_fields_url
  end
end
