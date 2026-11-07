require "test_helper"
require_relative "../support/checklists_world"
require_relative "../support/checklists_test_kinds"

# A kind can bring its own form section (ItemKind.form_partial), whose
# params are permitted by its form_params and kept by normalize_form.
class ChecklistItemFormSectionTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include ChecklistsWorld

  setup do
    host! "localhost"
    @view_paths = ChecklistItemsController.view_paths
    ChecklistItemsController.prepend_view_path(ChecklistsTestKinds::Rows::VIEWS)
    Checklists.register_item_kind(:rows, ChecklistsTestKinds::Rows)
    build_checklists_world
    @checklist = create_world_checklist(status: :draft)
  end

  teardown do
    Checklists.unregister_item_kind(:rows)
    ChecklistItemsController.view_paths = @view_paths
  end

  test "normalize_config keeps the section's params alongside the settings" do
    config = ChecklistsTestKinds::Rows.normalize_config({ "rows" => { "0" => { "name" => " Summer ", "share" => "10" }, "1" => { "name" => "" } } })

    assert_equal({ "rows" => [ { "name" => "Summer", "share" => 10 } ] }, config)
    assert_equal [ { rows: %i[name share] } ], ChecklistsTestKinds::Rows.permitted_config
  end

  test "the item form renders the kind's section and saves its rows" do
    with_feature do
      sign_in person(:admin).user
      get new_checklist_checklist_item_path(@checklist, kind: "rows")
      assert_response :success
      assert_select "#test-rows input[name='checklist_item[config][rows][0][name]']"

      post checklist_checklist_items_path(@checklist), params: { checklist_item: { kind: "rows", label: "Rules",
        config: { rows: { "0" => { name: "Summer", share: "10", secret: "x" }, "1" => { name: "Fall", share: "20" } } } } }
      item = @checklist.checklist_items.find_by!(label: "Rules")
      assert_equal [ { "name" => "Summer", "share" => 10 }, { "name" => "Fall", "share" => 20 } ], item.config["rows"]

      get edit_checklist_checklist_item_path(@checklist, item)
      assert_select "input[name='checklist_item[config][rows][1][name]'][value=Fall]"
    end
  end

  test "the kind validates its section" do
    with_feature do
      sign_in person(:admin).user
      post checklist_checklist_items_path(@checklist), params: { checklist_item: { kind: "rows", label: "Empty", config: { rows: { "0" => { name: "" } } } } }

      assert_response :unprocessable_entity
      assert_match "Add at least one row", response.body
    end
  end

  test "the live preview reads the section's params" do
    with_feature do
      sign_in person(:admin).user
      post preview_checklist_checklist_items_path(@checklist), params: { checklist_item: { kind: "rows", label: "Rules", config: { rows: { "0" => { name: "Summer", share: "10" } } } } }

      assert_response :success
      assert_match "Done", response.body
    end
  end
end
