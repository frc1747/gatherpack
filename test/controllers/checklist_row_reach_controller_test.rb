require "test_helper"
require_relative "../support/checklists_world"
require_relative "../support/checklists_test_kinds"

# Pages render a row the viewer reaches only through an item.
class ChecklistRowReachControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include ChecklistsWorld

  setup do
    host! "localhost"
    Checklists.register_item_kind(:pooled, ChecklistsTestKinds::Pooled)
    build_checklists_world
    @checklist = create_world_checklist
    add_rule(@checklist, :include, :team, team_id: @members.id)
    add_item(@checklist, :has_login, "Login")
    add_item(@checklist, :pooled, "Shifts")
    @dad = Person.create!(first_name: "Dad", last_name: "World", user: User.create!(email: "dad@example.com", password: "Password1!"))
    type = RelationshipType.create!(parent_label: "Relative of", child_label: "Relative of", permission: :added_by_admin, guardianship: :none)
    Relationship.create!(parent: @dad, child: person(:member), relationship_type: type, created_by: person(:admin))
    refresh(@checklist)
  end

  teardown do
    Checklists.unregister_item_kind(:pooled)
  end

  test "a pooled relative sees the shared item on the report and the person's page" do
    with_feature do
      sign_in @dad.user
      get checklist_path(@checklist)
      assert_response :success
      assert_match "Member World", response.body
      assert_match "1 of 2 shifts", response.body
      assert_no_match "MemberTwo World", response.body
      assert_no_match ">Login<", response.body.gsub(/\s+/, "")

      get checklists_path
      assert_match "Trip", response.body
    end
  end

  test "a recorded list keeps a row without an overall readable" do
    list = ChecklistList.record!(@checklist, by: @dad)
    with_feature do
      sign_in person(:admin).user
      get checklist_checklist_list_path(@checklist, list)
      assert_response :success
      assert_nil list.rows.first["overall"]
    end
  end
end
