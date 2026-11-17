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

  test "an item saved the old way can still be renamed by someone who can't set it up" do
    with_settings(feature_person_fields: "true", checklists_organizers: "Checklist Organizer > Club") do
      with_feature do
        secret = PersonField.create!(name: "Diet", data_type: :select, choices: %w[ Vegan Kosher None ], read_permission: "admin", write_permission: "admin")
        item = @checklist.checklist_items.create!(kind: "person_field", label: "Diet", config: { "field_id" => secret.id, "operator" => "any_of", "values" => "vegan" })
        item.update_column(:config, item.config.merge("values" => "vegan"))
        organizer = person(:organizer)
        @checklist.checklist_organizers.create!(person: organizer)
        sign_in organizer.user
        get edit_checklist_checklist_item_path(@checklist, item)
        assert_no_match "Kosher", response.body, "the field's other choices aren't shown to someone who can't read it"
        assert_select "input[type=checkbox][value=vegan][checked]"

        patch checklist_checklist_item_path(@checklist, item), params: { confirmed: "1", checklist_item: { label: "Renamed", config: { field_id: secret.id, operator: "any_of", values: [ "vegan" ] } } }
        assert_response :redirect
        assert_equal "Renamed", item.reload.label
      end
    end
  end

  test "old attendance links, by name or by an unnamed rule's default name, survive the form" do
    with_feature do
      sign_in person(:admin).user
      item = @checklist.checklist_items.create!(kind: "attendance", label: "Attendance", config: { "rules" => [ { "name" => "Summer", "share" => 10 }, { "name" => "Fall", "share" => 20 } ] })
      old = { "period_ids" => [], "rules" => [ { "name" => "Summer", "starts" => nil, "ends_on" => nil, "share" => 10, "weekly" => false, "with" => "Rule 2", "judge_after" => 0 },
        { "name" => nil, "starts" => nil, "ends_on" => nil, "share" => 20, "weekly" => false, "with" => nil, "judge_after" => 0 } ] }
      item.update_column(:config, old)
      kind = Checklists::Kinds::Attendance
      keyed = kind.keyed_rules(item.config["rules"])
      assert_equal keyed.last["key"], keyed.first["with"]

      item.config_params = { rules: keyed.each_with_index.to_h { |rule, index| [ index.to_s, rule ] } }
      assert kind.same_config?(old, item.config)
      assert_equal item.config["rules"].last["key"], item.config["rules"].first["with"]
    end
  end
end
