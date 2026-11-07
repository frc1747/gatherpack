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
    assert_includes rule.errors[:base], "Joining requires this form, so it can only ask everyone the checklist covers"
    assert add_checklist_rule(:covered).persisted?
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
