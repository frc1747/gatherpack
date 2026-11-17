require "test_helper"

class CalendarNoteBadgeTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    host! "localhost"
    admin = User.create!(email: "admin@example.com", password: "Password1!", admin: true)
    Person.create!(user: admin, first_name: "Ada", last_name: "Admin")
    sign_in admin
  end

  test "index shows the record a note is associated with" do
    get calendar_notes_path

    assert_response :success
    assert_select ".card-body", text: /Associated with\s+Alpha Team/
  end

  test "show renders a note associated with a record" do
    get calendar_note_path(calendar_notes(:one))

    assert_response :success
  end
end
