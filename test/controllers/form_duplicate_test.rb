require "test_helper"
require_relative "../support/forms_world"
require_relative "../support/settings_test_helper"

# Badge grants and the completion badge are admin-only settings, so a copy
# keeps them only when an admin makes it.
class FormDuplicateTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include FormsWorld
  include SettingsTestHelper

  setup do
    host! "localhost"
    build_person_fields_world
    @done = create_world_badge("Trip Ready")
    @form = create_world_form("Trip", team: @den_a, include: [ @den_a ], completion_badge: @done)
    @form.form_badge_grants.create!(badge: @health_officer_badge, access: :respond)
  end

  test "a manager's copy leaves off the badge grants and the completion badge" do
    with_settings(feature_forms: "true", feature_badges: "true") do
      as(:den_a_leader) do
        post form_badge_grants_path(@form), params: { form_badge_grant: { badge_id: @assistant_badge.id, access: "respond" } }
        assert_equal 1, @form.form_badge_grants.count, "managers can't add grants directly"

        post duplicate_form_path(@form)
        copy = Form.order(:created_at).last
        assert_not_equal @form, copy
        assert_equal person(:den_a_leader), copy.created_by
        assert_empty copy.form_badge_grants
        assert_nil copy.completion_badge
        follow_redirect!
        assert_select ".alert", text: /badge settings weren't copied/
      end
    end
  end

  test "an admin's copy keeps the badge grants and the completion badge" do
    with_settings(feature_forms: "true", feature_badges: "true") do
      as(:admin) do
        post duplicate_form_path(@form)
        copy = Form.order(:created_at).last
        assert_not_equal @form, copy
        assert_equal [ @health_officer_badge ], copy.form_badge_grants.map(&:badge)
        assert_equal @done, copy.completion_badge
        follow_redirect!
        assert_select ".alert", text: /badge settings weren't copied/, count: 0
      end
    end
  end

  test "an admin's copy leaves off badge settings that are no longer allowed" do
    # Saved before completion badges were kept apart from access: the
    # completion badge has a grant, and a grant's badge is another form's
    # completion badge.
    with_settings(feature_forms: "true", feature_badges: "true") do
      other_done = create_world_badge("Campout Ready")
      create_world_form("Campout", team: @den_a, include: [ @den_a ], completion_badge: other_done)
      @form.form_badge_grants.create!(badge: @assistant_badge, access: :read).update_column(:badge_id, other_done.id)
      create_world_form("Rules", team: @den_a, include: [ @den_a ]).form_badge_grants.create!(badge: @assistant_badge, access: :read).update_column(:badge_id, @done.id)

      as(:admin) do
        post duplicate_form_path(@form)
        copy = Form.order(:created_at).last
        assert_equal "Trip (copy)", copy.title
        assert_equal [ @health_officer_badge ], copy.form_badge_grants.map(&:badge)
        assert_nil copy.completion_badge
        follow_redirect!
        assert_select ".alert", text: /Some badge settings weren't copied because they're no longer allowed/
      end
    end
  end

  test "an admin's copy leaves off grants that are no longer in effect" do
    # Saved before grants needed a badge that is admin-assigned and whose team
    # exists.
    with_settings(feature_forms: "true", feature_badges: "true") do
      relaxed = create_world_badge("Helpers")
      @form.form_badge_grants.create!(badge: relaxed, access: :read)
      relaxed.update_columns(permission: Badge.permissions[:added_by_admin_or_self])
      orphaned = create_world_badge("Den B Helpers", team: @den_b)
      @form.form_badge_grants.create!(badge: orphaned, access: :read)
      orphaned.update_columns(team_id: SecureRandom.uuid)

      as(:admin) do
        post duplicate_form_path(@form)
        copy = Form.order(:created_at).last
        assert_equal "Trip (copy)", copy.title
        assert_equal [ @health_officer_badge ], copy.form_badge_grants.map(&:badge)
        assert_equal @done, copy.completion_badge
        follow_redirect!
        assert_select ".alert", text: /Some badge settings weren't copied because they're no longer allowed/
      end
    end
  end

  test "an admin's copy leaves off a completion badge members can now assign themselves" do
    with_settings(feature_forms: "true", feature_badges: "true") do
      @done.update!(permission: "added_by_admin_or_self")

      as(:admin) do
        post duplicate_form_path(@form)
        copy = Form.order(:created_at).last
        assert_equal "Trip (copy)", copy.title
        assert_nil copy.completion_badge
        assert_equal [ @health_officer_badge ], copy.form_badge_grants.map(&:badge)
        follow_redirect!
        assert_select ".alert", text: /Some badge settings weren't copied/
      end
    end
  end

  test "a copy of a form without badge settings says nothing about them" do
    plain = create_world_form("Campout", team: @den_a, include: [ @den_a ])
    with_settings(feature_forms: "true", feature_badges: "true") do
      as(:den_a_leader) do
        post duplicate_form_path(plain)
        follow_redirect!
        assert_select ".alert", text: /Form was duplicated/
        assert_select ".alert", text: /badge settings/, count: 0
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
