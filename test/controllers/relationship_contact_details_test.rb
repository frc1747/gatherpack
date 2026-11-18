require "test_helper"
require_relative "../support/person_fields_world"

class RelationshipContactDetailsTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include PersonFieldsWorld

  setup do
    host! "localhost"
    build_person_fields_world
    PersonField.ensure_system_fields!
    @contact = create_world_person("Contact", @other_org)
    @contact.update!(phone_number: "555-0100")
    person(:a1).update!(phone_number: "555-0199")
    @contact_type = RelationshipType.create!(parent_label: "Emergency contact of", child_label: "Has emergency contact", permission: :added_by_manager)
    @relationship = Relationship.create!(parent: @contact, child: person(:a1), relationship_type: @contact_type, created_by: person(:admin))
  end

  test "a leader of the child sees the contact's phone and email when the type shows them" do
    @contact_type.update!(show_contact_details: true)
    sign_in person(:den_a_leader).user

    get relationships_person_path(person(:a1))

    assert_response :success
    assert_select "em", text: @contact.identifier_name
    assert_select "a[href=?]", person_path(@contact), count: 0
    assert_select "a[href=?]", "tel:5550100", text: "555-0100"
    assert_select "a[href=?]", "mailto:contact@example.com", text: "contact@example.com"
  end

  test "the details are hidden when the type doesn't show them" do
    sign_in person(:den_a_leader).user

    get relationships_person_path(person(:a1))

    assert_response :success
    assert_select "em", text: @contact.identifier_name
    assert_not_includes response.body, "555-0100"
    assert_not_includes response.body, "contact@example.com"
  end

  test "the details follow the phone and email of the profile, even when their read levels exclude the viewer" do
    @contact_type.update!(show_contact_details: true)
    PersonField.system.where(system_source: %w[ phone_number user.email ]).update_all(read_permission: PersonField.read_permissions[:admin])
    sign_in person(:den_a_leader).user

    get relationships_person_path(person(:a1))

    assert_includes response.body, "555-0100"
    assert_includes response.body, "contact@example.com"
  end

  test "an archived field stays hidden, as on the profile" do
    @contact_type.update!(show_contact_details: true)
    PersonField.find_by!(system_source: "phone_number").archive!
    sign_in person(:den_a_leader).user

    get relationships_person_path(person(:a1))

    assert_not_includes response.body, "555-0100"
    assert_includes response.body, "contact@example.com"
  end

  test "a field hidden from profiles stays hidden" do
    @contact_type.update!(show_contact_details: true)
    PersonField.find_by!(system_source: "phone_number").update!(show_on_profile: false)
    sign_in person(:den_a_leader).user

    get relationships_person_path(person(:a1))

    assert_not_includes response.body, "555-0100"
    assert_includes response.body, "contact@example.com"
  end

  test "a relationship added while the type was open shows details once it's tightened and flagged" do
    type = RelationshipType.create!(parent_label: "Friend of", child_label: "Friend of", permission: :added_by_user)
    Relationship.create!(parent: @contact, child: person(:a2), relationship_type: type, created_by: person(:a2))

    type.update!(permission: :added_by_manager, show_contact_details: true)
    sign_in person(:den_a_leader).user
    get relationships_person_path(person(:a2))

    assert_includes response.body, "555-0100"
  end

  test "a contact with no phone shows a dash" do
    @contact.update!(phone_number: nil)
    @contact_type.update!(show_contact_details: true)
    sign_in person(:den_a_leader).user

    get relationships_person_path(person(:a1))

    assert_select "##{ActionView::RecordIdentifier.dom_id(@relationship, "phone")}", text: "Phone: —"
  end

  test "the leader still can't open the contact's profile" do
    @contact_type.update!(show_contact_details: true)
    sign_in person(:den_a_leader).user

    get person_path(@contact)
    assert_response :not_found

    # A 404 doesn't keep the session, so sign in again for the next request.
    sign_in person(:den_a_leader).user
    get relationships_person_path(@contact)
    assert_response :not_found
  end

  test "someone who can't see the child doesn't see the details" do
    @contact_type.update!(show_contact_details: true)
    sign_in person(:outsider).user

    get relationships_person_path(person(:a1))

    assert_response :not_found
  end

  test "the contact sees nothing new about the child" do
    sign_in @contact.user
    get relationships_person_path(@contact)
    assert_response :success
    before = response.body.scan(person(:a1).identifier_name).size

    @contact_type.update!(show_contact_details: true)

    get relationships_person_path(@contact)
    assert_response :success
    assert_equal before, response.body.scan(person(:a1).identifier_name).size
    assert_select "em", text: person(:a1).identifier_name
    assert_not_includes response.body, "555-0199"
    assert_not_includes response.body, "a1@example.com"

    get person_path(person(:a1))
    assert_response :not_found
  end

  test "the contact's page shows no contact details from this relationship, on either side" do
    @contact_type.update!(show_contact_details: true)
    sign_in person(:admin).user

    get relationships_person_path(@contact)

    assert_response :success
    assert_select "em, a", text: person(:a1).identifier_name
    assert_not_includes response.body, "555-0199"
    assert_not_includes response.body, "a1@example.com"
    assert_not_includes response.body, "555-0100"
    assert_not_includes response.body, "contact@example.com"
  end

  test "the child's own details aren't shown on the child's page" do
    @contact_type.update!(show_contact_details: true)
    sign_in person(:den_a_leader).user

    get relationships_person_path(person(:a1))

    assert_not_includes response.body, "555-0199"
    assert_not_includes response.body, "a1@example.com"
  end

  test "the flag gives no guardianship" do
    @contact_type.update!(show_contact_details: true)

    assert_empty person(:a1).guardians.where(id: @contact.id)
    assert_empty @contact.wards
    assert_not PersonPolicy.new(@contact.user, person(:a1)).show?
    assert_not PersonField.create!(name: "Allergies", data_type: :string, read_permission: "family", write_permission: "family").readable_by?(@contact, person(:a1))
    assert_equal [ person(:parent_a1) ], person(:a1).guardians.to_a
  end

  test "a member can't reach a stranger's details by adding them as a contact" do
    open_type = RelationshipType.create!(parent_label: "Friend of", child_label: "Friend of", permission: :added_by_user)

    assert_not open_type.update(show_contact_details: true)
  end
end
