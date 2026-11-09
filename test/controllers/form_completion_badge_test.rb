require "test_helper"
require_relative "../support/forms_world"
require_relative "../support/settings_test_helper"

# A completion badge marks who finished a form. The people who run the form
# choose who it asks, so the badge can't be one that grants access, and once
# a form has one, only admins change who it asks and who may answer.
class FormCompletionBadgeTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include FormsWorld
  include SettingsTestHelper

  setup do
    host! "localhost"
    build_person_fields_world
    @done = create_world_badge("Health Check Done")
  end

  def with_badges(**settings, &block)
    with_settings(feature_forms: "true", feature_badges: "true", feature_person_fields: "true", **settings, &block)
  end

  test "a manager can't award themselves a badge that grants access by completing their form" do
    with_badges do
      medical = create_world_field("Medical notes", read: "admin")
      medical.update!(badge_access: { @health_officer_badge.id => "read" })
      leader = person(:den_a_leader)
      form = create_world_form("Health check", team: @den_a, include: [ @den_a ], respond: "self", read: "family")
      add_choice(form, "Done?", [ "Yes" ])

      as(:admin) do
        patch form_path(form), params: { tab: "responses", form: { completion_badge_id: @health_officer_badge.id } }
        assert_response :unprocessable_entity
      end
      assert_nil form.reload.completion_badge

      as(:den_a_leader) do
        post form_audience_rules_path(form), params: { form_audience_rule: { effect: "include", target_type: "person", person_id: leader.id } }
        patch form_response_path(form, leader), params: { submit: "1", form_response: { answers: { done: "Yes" } } }
      end
      assert_not BadgeAssignment.exists?(badge: @health_officer_badge, person: leader)
      assert_not PersonField.find(medical.id).readable_by?(Person.find(leader.id), person(:b1))
    end
  end

  test "a completion badge without access is given to everyone who completes the form, managers included" do
    with_badges do
      form = create_world_form("Health check", team: @den_a, include: [ @den_a ], respond: "self", read: "family", completion_badge: @done)
      add_choice(form, "Done?", [ "Yes" ])

      respond(form, :a1, as: :a1, answers: { "done" => "Yes" })
      respond(form, :den_a_leader, as: :den_a_leader, answers: { "done" => "Yes" })

      assert BadgeAssignment.exists?(badge: @done, person: person(:a1))
      assert BadgeAssignment.exists?(badge: @done, person: person(:den_a_leader)), "a mentor's completed form still counts, for example for a sign-up position"
    end
  end

  test "once a form has a completion badge, only admins change who it asks and who may answer" do
    with_badges do
      form = create_world_form("Health check", team: @den_a, include: [ @den_a ], respond: "self", read: "family", completion_badge: @done)
      rule = form.form_audience_rules.first

      as(:den_a_leader) do
        get edit_form_path(form, tab: "audience")
        assert_select "#audience_locked", text: /only admins can change who it asks/
        assert_select "button", text: "Remove", count: 0
        assert_select "input[type=submit][value=?]", "Add person", count: 0
        get edit_form_path(form, tab: "permissions")
        assert_select "select[name=?][disabled]", "form[respond_permission]"

        post form_audience_rules_path(form), params: { form_audience_rule: { effect: "include", target_type: "person", person_id: person(:den_a_leader).id } }
        delete form_audience_rule_path(form, rule)
        patch form_path(form), params: { tab: "permissions", form: { respond_permission: "family" } }
      end
      assert_equal [ rule ], form.reload.form_audience_rules.to_a
      assert form.respond_self?

      as(:admin) do
        get edit_form_path(form, tab: "audience")
        assert_select "#audience_locked", count: 0
        post form_audience_rules_path(form), params: { form_audience_rule: { effect: "include", target_type: "person", person_id: person(:den_a_leader).id } }
        patch form_path(form), params: { tab: "permissions", form: { respond_permission: "family" } }
      end
      assert_equal 2, form.reload.form_audience_rules.count
      assert form.respond_family?
    end
  end

  test "once a form has a completion badge, only admins change its badge filter" do
    with_badges do
      form = create_world_form("Health check", team: @den_a, include: [ @den_a ], respond: "self", read: "family",
        completion_badge: @done, audience_badge: @assistant_badge)

      as(:den_a_leader) do
        get edit_form_path(form, tab: "audience")
        assert_select "select[name=?][disabled]", "form[audience_badge_id]"
        patch form_path(form), params: { tab: "audience", form: { audience_badge_id: "" } }
      end
      assert_equal @assistant_badge, form.reload.audience_badge

      as(:admin) do
        patch form_path(form), params: { tab: "audience", form: { audience_badge_id: "" } }
      end
      assert_nil form.reload.audience_badge
    end
  end

  test "without a completion badge, managers change who a form asks and who may answer" do
    with_badges do
      form = create_world_form("Health check", team: @den_a, include: [ @den_a ], respond: "self", read: "family")
      as(:den_a_leader) do
        post form_audience_rules_path(form), params: { form_audience_rule: { effect: "include", target_type: "person", person_id: person(:den_a_leader).id } }
        delete form_audience_rule_path(form, form.form_audience_rules.first)
        patch form_path(form), params: { tab: "permissions", form: { respond_permission: "family" } }
        patch form_path(form), params: { tab: "audience", form: { audience_badge_id: @assistant_badge.id } }
      end
      assert_equal [ "person" ], form.reload.form_audience_rules.map(&:target_type)
      assert form.respond_family?
      assert_equal @assistant_badge, form.audience_badge
    end
  end

  test "an admin who completes a form gets its completion badge" do
    with_badges do
      form = create_world_form("Health check", team: @den_a, include: [ @den_a, person(:admin) ], respond: "self", read: "family",
        completion_badge: @done)
      add_choice(form, "Done?", [ "Yes" ])

      respond(form, :admin, as: :admin, answers: { "done" => "Yes" })
      assert BadgeAssignment.exists?(badge: @done, person: person(:admin))
    end
  end

  test "a badge that grants access can't be a completion badge" do
    with_badges(forms_creator_badge: "Form Creator") do
      form = create_world_form("Health check", team: @den_a, include: [ @den_a ])
      assert form.update(completion_badge: @done)

      create_world_field("Medical notes", read: "admin").update!(badge_access: { @health_officer_badge.id => "read" })
      assert_not form.update(completion_badge: @health_officer_badge)
      assert_includes form.errors[:completion_badge], "can't be a badge that gives access to people's information"

      other = create_world_form("Trip", team: @den_a, include: [ @den_a ])
      reader = create_world_badge("Trip Reader")
      other.form_badge_grants.create!(badge: reader, access: :read)
      assert_not form.reload.update(completion_badge: reader)

      creator = create_world_badge("Form Creator")
      assert_equal creator, Form.creator_badge
      assert_not form.reload.update(completion_badge: creator)
    end
  end

  test "a completion badge can't be given access afterwards" do
    with_badges do
      create_world_form("Health check", team: @den_a, include: [ @den_a ], completion_badge: @done)

      grant = create_world_form("Trip").form_badge_grants.build(badge: @done, access: :read)
      assert_not grant.save
      assert_includes grant.errors[:badge], "is a form's completion badge, so it can't give access"

      field = create_world_field("Medical notes", read: "admin")
      assert_not field.update(badge_access: { @done.id => "read" })
      assert_empty PersonFieldBadgeGrant.where(badge: @done)
    end
  end

  test "the completion badge picker leaves out badges that grant access" do
    with_badges do
      form = create_world_form("Health check", team: @den_a, include: [ @den_a ])
      create_world_field("Medical notes", read: "admin").update!(badge_access: { @health_officer_badge.id => "read" })

      as(:admin) do
        get edit_form_path(form, tab: "responses")
        assert_select "select[name=?] option", "form[completion_badge_id]", text: "Health Check Done"
        assert_select "select[name=?] option", "form[completion_badge_id]", text: "Health Officer", count: 0
      end
    end
  end

  private

  def as(name)
    sign_in person(name).user
    yield
  ensure
    sign_out :user
  end
end
