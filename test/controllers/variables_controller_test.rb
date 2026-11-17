require "test_helper"

class VariablesControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    host! "localhost"

    @admin_user = User.create!(email: "admin@example.com", password: "Password1!", admin: true)
    Person.create!(user: @admin_user, first_name: "Ada", last_name: "Admin")

    @member_user = User.create!(email: "member@example.com", password: "Password1!")
    Person.create!(user: @member_user, first_name: "Sam", last_name: "Student")

    @variable = Variable.create!(name: "greeting", klass: "string", raw_value: "Hello")
  end

  test "a member cannot create a variable" do
    sign_in @member_user

    post variables_path, params: { variable: { name: "kiosk_open", klass: "string", raw_value: "planted" } }

    assert_nil Variable.find_by(name: "kiosk_open"), "a member created a variable"
    assert_redirected_to root_path
    assert_equal "You are not allowed to do that", flash[:notice]
  end

  test "an admin can create a variable" do
    sign_in @admin_user

    post variables_path, params: { variable: { name: "kiosk_open", klass: "string", raw_value: "yes" } }

    assert_redirected_to variable_path(Variable.find_by!(name: "kiosk_open"))
  end

  test "a member cannot open the new variable form" do
    sign_in @member_user

    get new_variable_path

    assert_redirected_to root_path
  end

  test "a member cannot list, show, update or delete variables" do
    sign_in @member_user

    get variables_path
    assert_redirected_to root_path

    get variable_path(@variable)
    assert_redirected_to root_path

    patch variable_path(@variable), params: { variable: { raw_value: "Changed" } }
    assert_redirected_to root_path
    assert_equal "Hello", @variable.reload.raw_value

    delete variable_path(@variable)
    assert_redirected_to root_path
    assert Variable.exists?(@variable.id)
  end

  test "an admin can show a variable" do
    sign_in @admin_user

    get variable_path(@variable)

    assert_response :success
  end
end
