require "test_helper"
require_relative "../support/checklists_world"

# Editing a field item as someone who couldn't have set it up: the form keeps
# the saved field, and only the label (not the config) can change.
class ChecklistPersonFieldItemsTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include ChecklistsWorld

  setup do
    host! "localhost"
    build_checklists_world
    @checklist = create_world_checklist
    add_rule(@checklist, :include, :team, team_id: @members.id)
    with_feature_settings do
      @secret = PersonField.create!(name: "Medical notes", data_type: :string, read_permission: "admin", write_permission: "admin")
      @open = PersonField.create!(name: "Allergies", data_type: :string, read_permission: "everyone", write_permission: "admin")
    end
    @item = add_item(@checklist, :person_field, "Notes", { field_id: @secret.id, operator: "none_of", values: "asthma" })
    with_feature_settings { @checklist.checklist_organizers.create!(person: person(:organizer)) }
    refresh(@checklist)
  end

  def with_feature_settings(&block)
    with_settings(feature_person_fields: "true", feature_checklists: "true", checklists_organizers: "Checklist Organizer > Club", &block)
  end

  test "the form keeps the saved field among the choices" do
    with_feature_settings do
      sign_in person(:organizer).user
      get edit_checklist_checklist_item_path(@checklist, @item)

      assert_response :success
      assert_select "select#checklist_item_config_field_id option[selected][value='#{@secret.id}']", 1
      assert_select "select#checklist_item_config_field_id option[value='#{@open.id}']", 1
    end
  end

  test "an editor who can't read the field can rename the item but not change its field" do
    with_feature_settings do
      sign_in person(:organizer).user
      get edit_checklist_checklist_item_path(@checklist, @item)
      assert_select "select#checklist_item_config_field_id option[value='#{@secret.id}']", 1

      patch checklist_checklist_item_path(@checklist, @item), params: { confirmed: "1", checklist_item: { label: "Renamed",
        config: { field_id: @secret.id, operator: "none_of", values: "asthma" } } }
      assert_response :redirect
      assert_equal "Renamed", @item.reload.label
      assert_equal @secret.id, @item.config["field_id"]

      patch checklist_checklist_item_path(@checklist, @item), params: { confirmed: "1", checklist_item: { label: "Again",
        config: { field_id: @open.id, operator: "none_of", values: "asthma" } } }
      assert_response :unprocessable_entity
      assert_equal "Renamed", @item.reload.label
      assert_equal @secret.id, @item.config["field_id"]
    end
  end

  test "an admin can change the field" do
    with_feature_settings do
      sign_in person(:admin).user
      patch checklist_checklist_item_path(@checklist, @item), params: { confirmed: "1", checklist_item: {
        config: { field_id: @open.id, operator: "none_of", values: "asthma" } } }

      assert_response :redirect
      assert_equal @open.id, @item.reload.config["field_id"]
    end
  end
end
