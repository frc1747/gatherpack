require "test_helper"
require_relative "../support/checklists_world"

# A form item's fix links show only to viewers who may use them; others
# see the label as plain text.
class ChecklistFormFixLinksTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include ChecklistsWorld

  setup do
    host! "localhost"
    travel_to Time.zone.local(2026, 10, 1, 10)
    build_checklists_world
    @checklist = create_world_checklist
    add_rule(@checklist, :include, :team, team_id: @members.id)
    @form = Form.create!(title: "Medical Release", team: @club, respond_permission: "family", read_permission: "family", status: :draft)
    @form.form_audience_rules.create!(effect: :include, target_type: :team, team: @members)
    @form.form_audience_rules.create!(effect: :exclude, target_type: :person, person: person(:member2))
    @form.form_questions.create!(kind: :signature, label: "Consent", signer: "guardian_if_minor")
    @form.update!(status: :open)
    @item = add_item(@checklist, :form_complete, "Medical", { form_ids: [ @form.id ] }, read_level: "team")
    person(:rookie).update!(birthday: Date.new(2013, 1, 1))
    person(:member).update!(birthday: Date.new(1990, 1, 1))

    response = @form.form_responses.create!(subject: person(:kid))
    response.start_submission!(person(:parent)).submit!(person(:parent), FormAccess.new(person(:parent), person(:kid), @form))
  end

  def page_for(viewer, name)
    sign_in person(viewer).user
    get person_checklists_path(person(name))
    assert_response :success
  end

  def with_features(&block)
    with_settings(feature_checklists: "true", feature_forms: "true") do
      refresh(@checklist)
      block.call
    end
  end

  test "fill it in: a link for the person, plain text for a teammate who sees it" do
    with_features do
      page_for(:member, :member)
      assert_select "a[href=?]", edit_form_response_path(@form, person(:member)), text: "Fill it in"

      page_for(:member2, :member)
      assert_select "a[href=?]", edit_form_response_path(@form, person(:member)), 0
      assert_match "Fill it in", response.body
    end
  end

  test "sign it: a link for the guardian who signs, plain text for a leader who can't" do
    with_features do
      page_for(:parent, :kid)
      assert_select "a[href=?]", form_response_path(@form, person(:kid)), text: "Sign it"

      page_for(:club_manager, :kid)
      assert_select "a[href=?]", form_response_path(@form, person(:kid)), 0
      assert_match "Sign it", response.body
    end
  end

  test "add them to the form's audience: a link for the form's managers only" do
    with_features do
      page_for(:club_manager, :member2)
      assert_select "a[href=?]", edit_form_path(@form, tab: "audience"), text: "Add them to the form's audience"

      page_for(:member2, :member2)
      assert_select "a[href=?]", edit_form_path(@form, tab: "audience"), 0
      assert_match "Add them to the form&#39;s audience", response.body
    end
  end

  test "add a guardian: a link for those who may edit the person, plain text for a teammate who sees it" do
    with_features do
      page_for(:club_manager, :rookie)
      assert_select "a[href=?]", relationships_person_path(person(:rookie)), text: "Add a guardian"

      page_for(:member2, :rookie)
      assert_select "a[href=?]", relationships_person_path(person(:rookie)), text: "Add a guardian", count: 0
      assert_match "Add a guardian", response.body
    end
  end
end
