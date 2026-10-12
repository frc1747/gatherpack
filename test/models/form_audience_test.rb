require "test_helper"
require_relative "../support/forms_world"
require_relative "../support/settings_test_helper"

class FormAudienceTest < ActiveSupport::TestCase
  include FormsWorld
  include SettingsTestHelper

  setup do
    build_person_fields_world
  end

  def ids(*names)
    names.map { |name| person(name).id }.sort
  end

  test "include rules add teams, badge holders, and people; exclude rules take them out" do
    form = create_world_form(include: [ @den_a ])
    assert_equal ids(:a1, :a2, :den_a_leader, :assistant), form.audience.ids.sort

    add_rule(form, @health_officer_badge)
    add_rule(form, person(:parent_a1))
    assert_equal ids(:a1, :a2, :den_a_leader, :assistant, :health_officer, :parent_a1), form.audience.ids.sort

    add_rule(form, person(:a2), effect: :exclude)
    add_rule(form, @assistant_badge, effect: :exclude)
    assert_equal ids(:a1, :den_a_leader, :health_officer, :parent_a1), form.audience.ids.sort
  end

  test "a team rule can leave out the team's managers" do
    form = create_world_form(include: [])
    add_rule(form, @pack, include_managers: false)
    assert_equal ids(:a1, :a2, :b1, :assistant), form.audience.ids.sort
  end

  test "the audience badge narrows the rules" do
    form = create_world_form(include: [ @pack ], audience_badge: @assistant_badge)
    assert_equal ids(:assistant), form.audience.ids
  end

  test "a form with no include rule asks nobody and can't open on schedule" do
    form = create_world_form(include: [], status: :draft, opens_at: 1.minute.ago)
    assert_empty form.audience
    assert_not form.openable?
    with_settings(feature_forms: "true") { FormScheduleJob.perform_now }
    assert form.reload.draft?
  end

  test "people no longer asked keep their response; only their leaders can still answer for them" do
    form = create_world_form
    add_choice(form, "Sandwich", [ "Slim 1" ])
    respond(form, :a1, as: :a1, answers: { "sandwich" => "Slim 1" })
    add_rule(form, person(:a1), effect: :exclude)

    assert_not form.in_audience?(person(:a1))
    assert_equal [ person(:a1).id ], form.former_subjects.ids
    assert FormAccess.new(person(:parent_a1), person(:a1), form).can_read?
    assert_not FormAccess.new(person(:a1), person(:a1), form).can_respond?
    assert_not FormAccess.new(person(:parent_a1), person(:a1), form).can_respond?
    assert FormAccess.new(person(:den_a_leader), person(:a1), form).can_respond?

    report = FormReport.new(form, viewer: person(:den_a_leader))
    row = report.rows.detect { |candidate| candidate.person == person(:a1) }
    assert_equal "no_longer_asked", row.status
    assert_equal "complete", row.response_status
    assert_equal 1, report.status_counts["no_longer_asked"]
  end

  test "badge grants let holders see or fill in responses within the badge's team" do
    form = create_world_form(respond: "family", read: "family")
    assert_not FormAccess.new(person(:assistant), person(:a1), form).can_read?

    grant = form.form_badge_grants.create!(badge: @assistant_badge, access: :read)
    form.form_badge_grants.reset
    assert FormAccess.new(person(:assistant), person(:a1), form).can_read?
    assert_not FormAccess.new(person(:assistant), person(:a1), form).can_respond?
    assert_not FormAccess.new(person(:assistant), person(:b1), form).can_read?, "a Den A badge doesn't reach Den B"

    grant.update!(access: :respond)
    form.form_badge_grants.reset
    assert FormAccess.new(person(:assistant), person(:a1), form).can_respond?
  end

  test "only admin-assigned badges can grant access" do
    badge = create_world_badge("Self Serve", team: @den_a)
    badge.update!(permission: :added_by_current_member)
    form = create_world_form
    grant = form.form_badge_grants.build(badge: badge, access: :read)
    assert_not grant.valid?
    assert grant.errors.key?(:badge)
  end

  test "the list forms agree with FormAccess, with rules, grants, and people no longer asked" do
    form = create_world_form(include: [ @den_a ], respond: "family", read: "family")
    add_choice(form, "Sandwich", [ "Slim 1" ])
    add_rule(form, person(:b1))
    form.form_badge_grants.create!(badge: @health_officer_badge, access: :respond)
    form.form_badge_grants.reset
    respond(form, :a2, as: :a2, answers: { "sandwich" => "Slim 1" })
    add_rule(form, person(:a2), effect: :exclude)

    PersonFieldsWorld::PEOPLE.each do |viewer|
      readable = PersonFieldsWorld::PEOPLE.select { |subject| FormAccess.new(person(viewer), person(subject), form).can_read? }.map { |name| person(name).id }
      respondable = PersonFieldsWorld::PEOPLE.select { |subject| FormAccess.new(person(viewer), person(subject), form).can_respond? }.map { |name| person(name).id }
      assert_equal readable.sort, form.readable_subjects_for(person(viewer)).ids.sort, "#{viewer} reading"
      assert_equal respondable.sort, form.respondable_subjects_for(person(viewer)).ids.sort, "#{viewer} responding"
    end
  end

  test "managers can only target what they manage" do
    form = create_world_form(team: @den_a, include: [ @den_a ])
    leader = person(:den_a_leader).user
    assert FormAudienceRulePolicy.new(leader, form.form_audience_rules.build(target_type: :team, team: @den_a)).create?
    assert_not FormAudienceRulePolicy.new(leader, form.form_audience_rules.build(target_type: :team, team: @den_b)).create?
    assert_not FormAudienceRulePolicy.new(leader, form.form_audience_rules.build(target_type: :person, person: person(:b1))).create?
    assert FormAudienceRulePolicy.new(leader, form.form_audience_rules.build(target_type: :badge, badge: @assistant_badge)).create?
    assert FormAudienceRulePolicy.new(person(:admin).user, form.form_audience_rules.build(target_type: :team, team: @den_b)).create?
  end

  test "duplicating copies the rules and grants, not the completion badge" do
    badge = create_world_badge("Meal Done")
    form = create_world_form(include: [ @den_a ], completion_badge: badge)
    add_rule(form, person(:b1))
    form.form_badge_grants.create!(badge: @health_officer_badge, access: :read)

    copy = form.duplicate!(title: "Meal Choices 2028")
    assert_equal form.audience.ids.sort, copy.audience.ids.sort
    assert_equal [ @health_officer_badge ], copy.form_badge_grants.map(&:badge)
    assert_nil copy.completion_badge
  end
end
