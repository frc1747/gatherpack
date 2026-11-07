require "test_helper"
require_relative "../support/checklists_world"

class FormAudienceChecklistRulesControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include ChecklistsWorld

  setup do
    host! "localhost"
    build_checklists_world
    @checklist = create_world_checklist("Joining")
    add_rule(@checklist, :include, :applicants, team_id: @joiners.id)
    @form = Form.create!(title: "Medical Release", team: @club, respond_permission: "family", read_permission: "family", status: :draft)
  end

  def with_features(&block)
    with_settings(feature_checklists: "true", feature_forms: "true", &block)
  end

  def add_rule_as(name, match: "covered")
    sign_in person(name).user
    post form_audience_rules_path(@form), params: { form_audience_rule: { effect: "include", target_type: "checklist", checklist_id: @checklist.id, checklist_match: match } }
  end

  test "a manager who runs the checklist adds it to a form's audience" do
    with_features do
      add_rule_as(:club_manager, match: "not_met")
      assert_redirected_to edit_form_path(@form, tab: "audience")
      rule = @form.form_audience_rules.sole
      assert rule.target_checklist?
      assert rule.checklist_not_met?
      assert_equal "Include people who haven't finished Joining: added. The form now asks 1 person.", flash[:notice]
    end
  end

  test "someone who doesn't run the checklist can't ask its people" do
    crew_form = Form.create!(title: "Crew Form", team: @crew, respond_permission: "family", read_permission: "family", status: :draft)
    with_features do
      sign_in person(:crew_manager).user
      post form_audience_rules_path(crew_form), params: { form_audience_rule: { effect: "include", target_type: "checklist", checklist_id: @checklist.id } }
      assert_not crew_form.form_audience_rules.exists?
    end
  end

  test "the audience tab offers checklists the manager runs, only while checklists are on" do
    with_settings(feature_forms: "true") do
      sign_in person(:club_manager).user
      get edit_form_path(@form, tab: "audience")
      assert_response :success
      assert_select "select[name='form_audience_rule[checklist_id]']", count: 0
    end
    with_features do
      get edit_form_path(@form, tab: "audience")
      assert_select "select[name='form_audience_rule[checklist_id]'] option", text: "Joining"
      assert_select "select[name='form_audience_rule[checklist_match]'] option", count: 3
    end
  end

  test "a form item picks forms the organizer manages and saves them all" do
    with_features do
      sign_in person(:club_manager).user
      get new_checklist_checklist_item_path(@checklist, kind: "form_complete")
      assert_response :success
      assert_select "select[name='checklist_item[config][form_ids][]'] option", text: "Medical Release"

      post checklist_checklist_items_path(@checklist), params: { checklist_item: { kind: "form_complete", label: "Medical", counts: "1", start_mode: "checklist",
        config: { form_ids: [ @form.id ], ever: "0" } }, confirmed: "1" }
      assert_redirected_to checklist_path(@checklist)
      item = @checklist.checklist_items.sole
      assert_equal({ "form_ids" => [ @form.id ], "ever" => false }, item.config)
      assert_equal "Completes Medical Release", item.kind_class.describe(item)
    end
  end

  test "a checklist rule is refused while checklists are off, and for an archived checklist" do
    with_settings(feature_forms: "true") do
      add_rule_as(:admin)
      assert_not @form.form_audience_rules.exists?
    end
    @checklist.update!(status: :archived)
    with_features do
      add_rule_as(:admin)
      assert_not @form.form_audience_rules.exists?
    end
  end

  test "an organizer can't make an item read a form they don't manage" do
    crew_checklist = create_world_checklist("Crew Trip", team: @crew)
    hidden = Form.create!(title: "Club Only", team: @club, respond_permission: "self_and_leaders", read_permission: "self_and_leaders", status: :draft)
    params = { checklist_item: { kind: "form_complete", label: "Sneaky", counts: "1", start_mode: "checklist", config: { form_ids: [ hidden.id ] } }, confirmed: "1" }
    with_features do
      sign_in person(:crew_manager).user
      post checklist_checklist_items_path(crew_checklist), params: params
      assert_redirected_to checklist_path(crew_checklist)
      assert_equal "You can only choose forms you manage.", flash[:alert]
      assert_not ChecklistItem.exists?(label: "Sneaky")

      post preview_checklist_checklist_items_path(crew_checklist), params: params
      assert_response :forbidden

      item = add_item(crew_checklist, :form_complete, "Medical", { form_ids: [ hidden.id ] })
      get edit_checklist_checklist_item_path(crew_checklist, item)
      assert_response :success
      assert_select "select[name='checklist_item[config][form_ids][]'] option[selected][value='#{hidden.id}']", text: "Club Only"
      patch checklist_checklist_item_path(crew_checklist, item), params: { checklist_item: { label: "Medical form", config: { form_ids: [ hidden.id ] } }, confirmed: "1" }
      assert_equal "Medical form", item.reload.label, "a form already on the item stays"

      crew_form = Form.create!(title: "Crew Form", team: @crew, respond_permission: "family", read_permission: "family", status: :draft)
      patch checklist_checklist_item_path(crew_checklist, item), params: { checklist_item: { label: "Medical form", config: { form_ids: [ hidden.id, crew_form.id ] } }, confirmed: "1" }
      assert_equal [ hidden.id, crew_form.id ], item.reload.config["form_ids"]
    end
  end
end
