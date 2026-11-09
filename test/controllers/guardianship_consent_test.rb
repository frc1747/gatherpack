require "test_helper"
require_relative "../support/person_fields_world"
require_relative "../support/settings_test_helper"

class GuardianshipConsentTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include PersonFieldsWorld
  include SettingsTestHelper

  setup do
    host! "localhost"
    build_person_fields_world
    @contact_of = RelationshipType.create!(parent_label: "Authorized contact of", child_label: "Has authorized contact", permission: :added_by_user, guardianship: :consented)
    person(:a1).update!(birthday: 19.years.ago.to_date)
    sign_in person(:a1).user
  end

  test "an adult whose guardianship has ended can give access back" do
    with_settings(guardianship_age_limit: "18") do
      assert_empty person(:a1).guardians

      get relationships_person_path(person(:a1))
      assert_includes response.body, "No longer has access to your restricted fields."
      assert_select "button", text: "Allow access"

      post person_relationships_path(person(:a1)), params: { relationship: { start_node: "#{@contact_of.id}:c", parent_id: person(:parent_a1).id } }
      assert_redirected_to person_path(person(:a1))

      assert_equal [ person(:parent_a1) ], person(:a1).guardians.to_a
      get relationships_person_path(person(:a1))
      assert_select "button", text: "Allow access", count: 0
    end
  end

  test "nothing is shown while guardianship is still active" do
    get relationships_person_path(person(:a1))

    assert_not_includes response.body, "No longer has access"
  end

  test "the guardian can't grant themselves consent" do
    sign_out :user
    sign_in person(:parent_a1).user

    post person_relationships_path(person(:parent_a1)), params: { relationship: { start_node: "#{@contact_of.id}:p", child_id: person(:a1).id } }

    assert_not Relationship.exists?(relationship_type: @contact_of)
  end
end
