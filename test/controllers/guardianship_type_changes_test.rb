require "test_helper"
require_relative "../support/person_fields_world"
require_relative "../support/settings_test_helper"

# A relationship type's links were made under its old guardianship setting,
# so a type with links can't be made to grant more guardianship.
class GuardianshipTypeChangesTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include PersonFieldsWorld
  include SettingsTestHelper

  setup do
    host! "localhost"
    build_person_fields_world
    @family = RelationshipType.create!(parent_label: "Parent", child_label: "Child", permission: :added_by_user, guardianship: :none)
    @medical = create_world_field("Medical Notes", read: "guardians", write: "admin")
    person(:a1).set_field_value(@medical, "epilepsy, rescue meds in bag")

    # A student in another den records themself as A1's "Parent", which the
    # type allows while it grants nothing.
    sign_in person(:b1).user
    post person_relationships_path(person(:b1)), params: { relationship: {
      relationship_type_id: @family.id, start_node: "#{@family.id}:p", child_id: person(:a1).id
    } }
    sign_out :user
    @link = Relationship.find_by(parent: person(:b1), child: person(:a1), relationship_type: @family)
  end

  test "making a linked type a minor guardianship doesn't make its links guardians" do
    assert @link

    sign_in person(:admin).user
    patch relationship_type_path(@family), params: { relationship_type: { permission: "added_by_manager", guardianship: "minor" } }
    assert_response :unprocessable_entity
    assert_includes response.body, "create a new type"
    sign_out :user

    assert @family.reload.guardianship_none?
    assert_not person(:a1).guardians.include?(person(:b1))
    with_settings(feature_person_fields: "true") do
      sign_in person(:b1).user
      get person_path(person(:a1))
      assert_not_includes response.body, "epilepsy"
    end
  end

  test "making a linked type consented doesn't skip the child's consent for old links" do
    sign_in person(:admin).user
    patch relationship_type_path(@family), params: { relationship_type: { guardianship: "consented" } }
    sign_out :user

    assert @family.reload.guardianship_none?
    assert_not person(:a1).guardians.include?(person(:b1))
  end

  test "a minor guardianship type with links can't become consented" do
    assert_not @parent_of.update(guardianship: :consented)
    assert @parent_of.errors[:guardianship].any?
  end

  test "narrowing a linked type's guardianship is allowed" do
    consented = RelationshipType.create!(parent_label: "Contact of", child_label: "Has contact", permission: :added_by_admin, guardianship: :consented)
    Relationship.create!(parent: person(:parent_a2), child: person(:a2), relationship_type: consented, created_by: person(:admin))

    assert consented.update(guardianship: :minor)
    assert @parent_of.update(guardianship: :none)
    assert_not person(:a1).guardians.include?(person(:parent_a1))
  end

  test "a type without links can be made a guardianship, and new links of it are guardians" do
    sign_in person(:admin).user
    post relationship_types_path, params: { relationship_type: { parent_label: "Guardian of", child_label: "Ward of", permission: "added_by_admin", guardianship: "none" } }
    type = RelationshipType.find_by!(parent_label: "Guardian of")
    patch relationship_type_path(type), params: { relationship_type: { guardianship: "minor" } }
    assert type.reload.guardianship_minor?

    Relationship.create!(parent: person(:parent_a2), child: person(:b1), relationship_type: type, created_by: person(:admin))
    assert_includes person(:b1).guardians, person(:parent_a2)
  end

  test "the edit form explains the rule for a type with links" do
    sign_in person(:admin).user

    get edit_relationship_type_path(@family)
    assert_select ".form-text", text: /already has links/

    unlinked = RelationshipType.create!(parent_label: "Coach of", child_label: "Coached by", permission: :added_by_admin)
    get edit_relationship_type_path(unlinked)
    assert_select ".form-text", text: /already has links/, count: 0
  end
end
