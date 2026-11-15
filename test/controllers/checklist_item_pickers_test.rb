require "test_helper"
require_relative "../support/checklists_world"

# The attendance rule's "counted together with" and the profile field test's
# values are pickers on the item form.
class ChecklistItemPickersTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include ChecklistsWorld

  setup do
    host! "localhost"
    build_checklists_world
    @checklist = create_world_checklist(status: :draft)
  end

  test "an attendance rule picks the rule it's counted together with, and renaming keeps the link" do
    with_feature do
      sign_in person(:admin).user
      get new_checklist_checklist_item_path(@checklist, kind: "attendance")
      assert_select "select[name='checklist_item[config][rules][0][with]']"
      assert_select "input[name='checklist_item[config][rules][0][key]']"

      post checklist_checklist_items_path(@checklist), params: { checklist_item: { kind: "attendance", label: "Attendance", config: { rules: {
        "0" => { key: "aaa", name: "Summer", share: "10", with: "bbb" }, "1" => { key: "bbb", name: "Fall", share: "20" } } } } }
      item = @checklist.checklist_items.find_by!(label: "Attendance")
      assert_equal "bbb", item.config["rules"].first["with"]

      get edit_checklist_checklist_item_path(@checklist, item)
      assert_select "select[name='checklist_item[config][rules][0][with]'] option[value=bbb][selected]", text: "Fall"
      assert_select "select[name='checklist_item[config][rules][0][with]'] option[value=aaa]", false, "a rule isn't offered itself"

      patch checklist_checklist_item_path(@checklist, item), params: { checklist_item: { label: "Attendance", config: { rules: {
        "0" => { key: "aaa", name: "Summer", share: "10", with: "bbb" }, "1" => { key: "bbb", name: "Autumn", share: "20" } } } } }
      assert_equal "Autumn", Checklists::Kinds::Attendance.rules(item.reload).first.with
    end
  end

  test "a choice field's values are ticked, and any other field's typed" do
    with_settings(feature_person_fields: "true") do
      with_feature do
        size = PersonField.create!(name: "Size", data_type: :select, choices: [ "S", "Medium, wide" ], read_permission: "admin", write_permission: "admin")
        note = PersonField.create!(name: "Note", data_type: :text, read_permission: "admin", write_permission: "admin")
        sign_in person(:admin).user
        get new_checklist_checklist_item_path(@checklist, kind: "person_field")
        assert_select "fieldset[data-field-id='#{size.id}'] input[type=checkbox][value='Medium, wide']"
        assert_select "fieldset[data-field-id='#{note.id}']", false
        assert_select "input[type=text][name='checklist_item[config][values][]']"

        post checklist_checklist_items_path(@checklist), params: { checklist_item: { kind: "person_field", label: "Size", config: {
          field_id: size.id, operator: "any_of", values: [ "", "Medium, wide" ] } } }
        item = @checklist.checklist_items.find_by!(label: "Size")
        assert_equal [ "Medium, wide" ], item.config["values"]

        get edit_checklist_checklist_item_path(@checklist, item)
        assert_select "input[type=checkbox][value='Medium, wide'][checked]"
      end
    end
  end
end
