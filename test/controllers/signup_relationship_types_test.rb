require "test_helper"
require_relative "../support/signups_world"

# Sign up others only trusts relationship types members can't add
# themselves (SignupSheet.trusted_relationship_types).
class SignupRelationshipTypesTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include SignupsWorld

  setup do
    host! "localhost"
    travel_to Time.zone.parse("2026-10-15 09:00")
    build_signups_world
    @friend_of = RelationshipType.create!(parent_label: "Friend of", child_label: "Friend of", permission: :added_by_participant)
    @guardian_of = RelationshipType.create!(parent_label: "Guardian of", child_label: "Ward of", permission: :added_by_manager)
  end

  teardown { travel_back }

  test "a member can't cancel a classmate's sign-up by adding a relationship themselves" do
    sheet = create_world_sheet
    sheet.update_column(:others_relationship_type_ids, [ @friend_of.id ])
    position = sheet.signup_positions.create!(name: "Cashier", capacity: 5)
    classmate_signup = create_world_signup(position, :student)

    sign_in person(:student2).user
    post person_relationships_path(person(:student2)),
      params: { relationship: { start_node: "#{@friend_of.id}:p", child_id: person(:student).id } }
    assert Relationship.exists?(parent: person(:student2), child: person(:student)), "the member added the relationship themselves"

    delete signup_sheet_signup_path(sheet, classmate_signup)

    assert classmate_signup.reload.active?
    assert_not_includes sheet.takers_for(person(:student2)), person(:student)
  end

  test "sign up others works through a type admins or managers add" do
    sheet = create_world_sheet(others_relationship_type_ids: [ @guardian_of.id ])
    slot = slot_for(sheet.signup_positions.create!(name: "Cashier", capacity: 5))
    Relationship.create!(parent: person(:parent), child: person(:student), relationship_type: @guardian_of, created_by: person(:admin))
    sign_in person(:parent).user

    assert_difference "Signup.count" do
      post signup_sheet_signups_path(sheet), params: { signup: { signup_slot_id: slot.id, person_id: person(:student).id } }
    end
    signup = Signup.order(:created_at).last
    assert_equal [ person(:student), person(:parent) ], [ signup.person, signup.signed_up_by ]

    delete signup_sheet_signup_path(sheet, signup)
    assert signup.reload.cancelled?
  end

  test "a sheet can't be set to trust a type members add themselves, and the form doesn't offer one" do
    sheet = create_world_sheet

    assert_not sheet.update(others_relationship_type_ids: [ @guardian_of.id, @friend_of.id ])
    assert_equal [ "can only use relationships that admins or managers add" ], sheet.errors[:others_relationship_type_ids]
    assert sheet.reload.update(others_relationship_type_ids: [ @guardian_of.id, @parent_of.id ])

    sign_in person(:admin).user
    get edit_signup_sheet_path(sheet)
    assert_response :success
    assert_select "input[name='signup_sheet[others_relationship_type_ids][]'][value=?]", @guardian_of.id
    assert_select "input[name='signup_sheet[others_relationship_type_ids][]'][value=?]", @friend_of.id, count: 0

    patch signup_sheet_path(sheet), params: { signup_sheet: { others_relationship_type_ids: [ "", @friend_of.id ] } }
    assert_response :unprocessable_entity
    assert_equal [ @guardian_of.id, @parent_of.id ].sort, sheet.reload.others_relationship_type_ids.sort
  end

  test "a saved type members add themselves is ignored, and the sheet still saves" do
    sheet = create_world_sheet
    sheet.update_column(:others_relationship_type_ids, [ @friend_of.id, @parent_of.id ])
    Relationship.create!(parent: person(:student2), child: person(:student), relationship_type: @friend_of, created_by: person(:student2))

    assert_equal [ person(:student2) ], sheet.takers_for(person(:student2)).to_a
    assert_equal [ person(:student) ], sheet.takers_for(person(:parent)).to_a
    assert sheet.update(title: "Renamed")
  end
end
