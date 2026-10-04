require "test_helper"

class RelationshipTypesControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    host! "localhost"
    @admin = User.create!(email: "admin@example.com", password: "Password1!", admin: true)
    Person.create!(user: @admin, first_name: "Ada", last_name: "Admin")
    sign_in @admin
  end

  test "an admin can mark a type as a guardianship" do
    type = relationship_types(:one)

    get edit_relationship_type_path(type)
    assert_response :success
    assert_select "select[name='relationship_type[guardianship]'] option", text: "Guardian while the child is a minor"

    patch relationship_type_path(type), params: { relationship_type: { guardianship: "minor" } }
    assert_redirected_to relationship_type_path(type)
    assert type.reload.guardianship_minor?

    get relationship_types_path
    assert_select ".badge", text: "Guardian"
  end

  test "a guardianship type with a member-level permission is rejected" do
    type = relationship_types(:one)

    patch relationship_type_path(type), params: { relationship_type: { guardianship: "minor", permission: "added_by_user" } }

    assert_response :unprocessable_entity
    assert type.reload.guardianship_none?
  end
end
