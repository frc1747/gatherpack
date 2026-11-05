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

  test "the form lists what guardians can do" do
    get new_relationship_type_path

    assert_response :success
    assert_guardian_grants_listed
  end

  test "the form and show page list a line a feature registers" do
    original = RelationshipType.guardian_grants
    RelationshipType.register_guardian_grant("do something new")
    type = relationship_types(:one)
    type.update!(guardianship: :minor)

    get edit_relationship_type_path(type)
    assert_select ".form-text li", text: "do something new"

    get relationship_type_path(type)
    assert_select ".form-text li", text: "do something new"
  ensure
    RelationshipType.instance_variable_set(:@guardian_grants, original)
  end

  test "the show page lists what guardians can do only for a flagged type" do
    type = relationship_types(:one)

    get relationship_type_path(type)
    assert_response :success
    assert_select "p", text: "Guardians can:", count: 0
    assert_select "p", text: /Don't use guardianship/, count: 0

    type.update!(guardianship: :consented)

    get relationship_type_path(type)
    assert_guardian_grants_listed
  end

  test "editing a type with relationships carries the confirmation" do
    type = relationship_types(:one)

    get edit_relationship_type_path(type)

    assert_select ".form-inputs[data-controller='guardianship-confirm'][data-guardianship-confirm-saved-value='false']" \
      "[data-guardianship-confirm-message-value='This makes the parent side of 1 relationship a guardian.']"
  end

  test "editing a flagged type with relationships carries the reverse confirmation" do
    type = relationship_types(:one)
    type.update!(guardianship: :minor)

    get edit_relationship_type_path(type)

    assert_select ".form-inputs[data-controller='guardianship-confirm'][data-guardianship-confirm-saved-value='true']" \
      "[data-guardianship-confirm-message-value='This stops the parent side of 1 relationship being a guardian.']"
  end

  test "a rejected change keeps the confirmation based on the saved value" do
    type = relationship_types(:one)

    patch relationship_type_path(type), params: { relationship_type: { guardianship: "minor", permission: "added_by_user" } }

    assert_response :unprocessable_entity
    assert_select ".form-inputs[data-guardianship-confirm-saved-value='false']"
  end

  test "a new type or a type with no relationships doesn't carry a confirmation" do
    get new_relationship_type_path
    assert_select "[data-controller='guardianship-confirm']", count: 0

    type = RelationshipType.create!(parent_label: "Parent of", child_label: "Child of", permission: :added_by_admin)

    get edit_relationship_type_path(type)
    assert_select "[data-controller='guardianship-confirm']", count: 0
  end

  private

  def assert_guardian_grants_listed
    assert_select ".form-text p", text: "Guardians can:"
    RelationshipType.guardian_grants.each do |grant|
      assert_select ".form-text li", text: grant
    end
    assert_select ".form-text p", text: "Don't use guardianship just to link people. For an emergency contact, use a type with no guardianship."
  end
end
