require "test_helper"
require_relative "../support/checklists_world"
require_relative "../support/checklists_test_kinds"

# Any setting declared list: true keeps an array of values, of any type.
class ChecklistListSettingsTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include ChecklistsWorld

  setup do
    host! "localhost"
    Checklists.register_item_kind(:lists, ChecklistsTestKinds::Lists)
    build_checklists_world
    @checklist = create_world_checklist(status: :draft)
  end

  teardown do
    Checklists.unregister_item_kind(:lists)
  end

  test "list settings are permitted as arrays and cast per value" do
    assert_equal [ { forms: [] }, { years: [] }, :mode ], ChecklistsTestKinds::Lists.permitted_config
    assert_equal({ "forms" => %w[consent photo], "years" => [ 2026, 2027 ], "mode" => "any" },
      ChecklistsTestKinds::Lists.normalize_config({ "forms" => [ "consent", "", "photo" ], "years" => %w[2026 2027], "mode" => "any" }))
    assert Checklists::Kinds::Badge.settings.first.list?, "badges are always a list"
  end

  test "the item form posts and saves several values for a list setting" do
    with_feature do
      sign_in person(:admin).user
      get new_checklist_checklist_item_path(@checklist, kind: "lists")
      assert_select "select[multiple][name='checklist_item[config][forms][]']"
      assert_select "select:not([multiple])[name='checklist_item[config][mode]']"

      post checklist_checklist_items_path(@checklist), params: { checklist_item: { kind: "lists", label: "Forms",
        config: { forms: %w[consent medical], years: [ "2026" ], mode: "all" } } }
      item = @checklist.checklist_items.find_by!(label: "Forms")
      assert_equal %w[consent medical], item.config["forms"]
      assert_equal [ 2026 ], item.config["years"]
      assert_equal "all", item.config["mode"]
    end
  end
end
