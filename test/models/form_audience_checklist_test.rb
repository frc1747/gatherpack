require "test_helper"
require_relative "../support/checklists_world"

class FormAudienceChecklistTest < ActiveSupport::TestCase
  include ChecklistsWorld

  setup do
    travel_to Time.zone.local(2026, 10, 1, 10)
    build_checklists_world
    @checklist = create_world_checklist("Joining")
    add_rule(@checklist, :include, :team, team_id: @members.id)
    add_rule(@checklist, :include, :applicants, team_id: @joiners.id)
    @safety_item = add_item(@checklist, :badge, "Safety", { badge_ids: [ @safety.id ] })
    @form = Form.create!(title: "Medical Release", team: @club, respond_permission: "family", read_permission: "family", status: :draft)
  end

  def add_checklist_rule(match = :covered, checklist: @checklist, effect: :include)
    @form.form_audience_rules.create!(effect: effect, target_type: :checklist, checklist: checklist, checklist_match: match).tap { @form.form_audience_rules.reset }
  end

  def audience_names
    ids = @form.audience.ids
    @people.select { |_, candidate| ids.include?(candidate.id) }.keys.sort
  end

  test "asks everyone a checklist covers, applicants on no team included" do
    with_feature do
      rule = add_checklist_rule
      assert_equal %i[applicant kid member member2 rookie], audience_names
      assert_equal "Include everyone Joining covers", rule.description
      assert @form.openable?
    end
  end

  test "asks the people who have, or haven't, finished it" do
    give_badge(:member, @safety)
    with_feature do
      refresh(@checklist)
      finished = add_checklist_rule(:met)
      assert_equal %i[member], audience_names
      assert_equal "Include people who have finished Joining", finished.description

      finished.destroy!
      @form.form_audience_rules.reset
      add_checklist_rule(:not_met)
      assert_equal %i[applicant kid member2 rookie], audience_names
    end
  end

  test "an exclude rule leaves a checklist's people out" do
    with_feature do
      @form.form_audience_rules.create!(effect: :include, target_type: :team, team: @club)
      add_checklist_rule(effect: :exclude)
      assert_not_includes audience_names, :member
      assert_includes audience_names, :organizer
    end
  end

  test "while checklists are turned off the rule asks nobody" do
    rule = add_checklist_rule
    assert_empty @form.audience
    assert_equal "Include everyone Joining covers (ignored while Checklists are turned off)", rule.description
  end

  test "a rule needs its checklist, and other targets drop it" do
    rule = @form.form_audience_rules.build(effect: :include, target_type: :checklist)
    assert_not rule.valid?
    assert_includes rule.errors[:checklist], "can't be blank"

    team_rule = @form.form_audience_rules.create!(effect: :include, target_type: :team, team: @club, checklist: @checklist, checklist_match: :met)
    assert_nil team_rule.checklist_id
    assert team_rule.checklist_covered?
  end

  test "the same checklist can't be added twice, but each match once" do
    add_checklist_rule
    assert_not @form.form_audience_rules.build(effect: :include, target_type: :checklist, checklist: @checklist).valid?
    assert @form.form_audience_rules.build(effect: :include, target_type: :checklist, checklist: @checklist, checklist_match: :met).valid?
    other = create_world_checklist("Other")
    assert @form.form_audience_rules.build(effect: :include, target_type: :checklist, checklist: other).valid?
  end

  test "only everyone covered for a checklist that requires this form" do
    add_item(@checklist, :form_complete, "Medical", { form_ids: [ @form.id ] })
    rule = @form.form_audience_rules.build(effect: :include, target_type: :checklist, checklist: @checklist, checklist_match: :not_met)
    assert_not rule.valid?
    assert_includes rule.errors[:base], "Joining requires this form, directly or through a checklist it requires, so it can only ask everyone the checklist covers"
    assert add_checklist_rule(:covered).persisted?
  end

  test "the form can't be required later, by the checklist or one that requires it" do
    add_checklist_rule(:not_met)
    item = @checklist.checklist_items.new(kind: "form_complete", label: "Medical")
    item.config_params = { form_ids: [ @form.id ] }
    assert_not item.save
    assert_includes item.errors[:base], "Medical Release asks only people who have or haven't finished Joining, so Joining can't require it"

    inner = create_world_checklist("Inner")
    add_item(@checklist, :checklist, "Inner", { checklist_id: inner.id })
    nested = inner.checklist_items.new(kind: "form_complete", label: "Medical")
    nested.config_params = { form_ids: [ @form.id ] }
    assert_not nested.save, "Joining requires Inner, so Inner can't require the form either"
    assert @form.duplicate!(title: "Medical Release copy").persisted?, "the rule stays valid, so Duplicate works"
  end

  test "a checklist that requires the form through another can't ask by status, and can't take one on later" do
    inner = create_world_checklist("Inner")
    add_item(inner, :form_complete, "Medical", { form_ids: [ @form.id ] })
    add_item(@checklist, :checklist, "Inner", { checklist_id: inner.id })
    rule = @form.form_audience_rules.build(effect: :include, target_type: :checklist, checklist: @checklist, checklist_match: :met)
    assert_not rule.valid?
    assert_includes rule.errors[:base], "Joining requires this form, directly or through a checklist it requires, so it can only ask everyone the checklist covers"

    outer = create_world_checklist("Outer")
    @form.form_audience_rules.create!(effect: :include, target_type: :checklist, checklist: outer, checklist_match: :met)
    link = outer.checklist_items.new(kind: "checklist", label: "Joining")
    link.config_params = { checklist_id: @checklist.id }
    assert_not link.save
    assert_match "so Outer can't require it", link.errors[:base].to_sentence
  end

  test "finished or not only for a form of the checklist's team or below; everyone covered for others" do
    crew_form = Form.create!(title: "Crew Form", team: @crew, respond_permission: "family", read_permission: "family", status: :draft)
    assert crew_form.form_audience_rules.build(effect: :include, target_type: :checklist, checklist: @checklist, checklist_match: :met).valid?

    other = create_world_team("Elsewhere")
    far_form = Form.create!(title: "Far Form", team: other, respond_permission: "family", read_permission: "family", status: :draft)
    rule = far_form.form_audience_rules.build(effect: :include, target_type: :checklist, checklist: @checklist, checklist_match: :not_met)
    assert_not rule.valid?
    assert_includes rule.errors[:checklist_match], "can only be everyone Joining covers, because this form isn't in Club or a team below it"
    assert far_form.form_audience_rules.build(effect: :include, target_type: :checklist, checklist: @checklist).valid?

    with_feature do
      kept = add_checklist_rule(:not_met)
      @form.update_columns(team_id: other.id)
      assert_empty @form.reload.audience, "a form moved out of the team stops asking by status"
      assert_match "ignored: the form isn't in Club", kept.reload.description
    end
  end

  test "while checklists are off a checklist rule doesn't make the form openable" do
    add_checklist_rule
    assert_not @form.reload.openable?
    with_feature { assert @form.reload.openable? }
  end

  test "an overall change marks checklists reading a form that asks by it, and a population change marks them all" do
    add_checklist_rule(:met)
    trip = create_world_checklist("Trip")
    add_item(trip, :form_complete, "Medical", { form_ids: [ @form.id ] })
    other = create_world_checklist("Unrelated")
    add_item(other, :has_login, "Login")
    with_feature do
      refresh(@checklist)
      refresh(trip)
      refresh(other)
      ChecklistRefresh.delete_all

      give_badge(:member, @safety)
      ChecklistRefresh.delete_all
      refresh(@checklist)
      assert_equal "met", stored_status(@checklist, :member)
      assert_equal [ person(:member).id ], ChecklistRefresh.where(checklist: trip).pluck(:person_id)
      assert_not ChecklistRefresh.exists?(checklist: other)

      ChecklistRefresh.delete_all
      add_rule(@checklist, :exclude, :person, person_id: person(:rookie).id)
      assert ChecklistRefresh.exists?(checklist: trip, person_id: nil)
      assert_not ChecklistRefresh.exists?(checklist: other)
    end
  end

  test "a checklist a form asks can't be deleted" do
    add_checklist_rule
    assert_not @checklist.destroy
    assert Checklist.exists?(@checklist.id)
  end

  test "copying the form keeps the rule" do
    add_checklist_rule(:met)
    copy = @form.duplicate!(title: "Medical Release 2027")
    rule = copy.form_audience_rules.sole
    assert rule.target_checklist?
    assert_equal @checklist, rule.checklist
    assert rule.checklist_met?
  end

  test "applicants asked through the checklist can finish its form item" do
    item = add_item(@checklist, :form_complete, "Medical", { form_ids: [ @form.id ] })
    with_settings(feature_checklists: "true", feature_forms: "true") do
      add_checklist_rule
      @form.update!(status: :open)
      assert_equal "not_met", evaluate(@checklist, :applicant, item).status
      assert_equal "No response yet", evaluate(@checklist, :applicant, item).detail

      response = @form.form_responses.create!(subject: person(:applicant))
      submission = response.start_submission!(person(:applicant))
      submission.submit!(person(:applicant), FormAccess.new(person(:applicant), person(:applicant), @form))
      assert_equal "met", evaluate(@checklist, :applicant, item).status
    end
  end

  test "a completion badge's team must hold the checklist" do
    badge = Badge.create!(name: "Cleared", short: "C", color: "#336699", badge_type: badge_types(:one), team: @crew, permission: :added_by_admin)
    @form.update!(completion_badge: badge)
    rule = @form.form_audience_rules.build(effect: :include, target_type: :checklist, checklist: @checklist)
    assert_not rule.valid?
    assert_includes rule.errors[:base].join, "because the completion badge belongs to it"
  end
end
