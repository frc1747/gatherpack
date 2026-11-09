require "test_helper"
require_relative "../support/forms_world"
require_relative "../support/settings_test_helper"

# A badge grants access to a form's responses only while admins choose its
# holders and, for a team badge, while its team exists.
class FormBadgeGrantRulesTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include FormsWorld
  include SettingsTestHelper

  setup do
    host! "localhost"
    build_person_fields_world
    # The assistant also belongs to Pack, so they keep seeing the pack's people.
    Membership.create!(person: person(:assistant), team: @pack)
    @form = create_world_form
    add_choice(@form, "Meal", %w[ Pizza Tacos ])
    respond(@form, :a1, as: :a1, answers: { "meal" => "Pizza" })
    respond(@form, :b1, as: :b1, answers: { "meal" => "Tacos" })
  end

  def with_badges(&block)
    with_settings(feature_forms: "true", feature_badges: "true", &block)
  end

  def delete_den_a
    sign_in person(:pack_leader).user
    delete team_path(@den_a)
    sign_out :user
    assert_not Team.exists?(@den_a.id)
    assert BadgeAssignment.exists?(badge: @assistant_badge, person: person(:assistant)), "the badge and its assignment stay"
  end

  test "a badge that grants form access can't be made self-assignable while the grant stands" do
    @form.form_badge_grants.create!(badge: @health_officer_badge, access: :read)

    sign_in person(:admin).user
    patch badge_path(@health_officer_badge), params: { badge: { permission: "added_by_admin_or_self" } }

    assert_response :unprocessable_entity
    assert @health_officer_badge.reload.added_by_admin?
  end

  test "a form grant from a badge that lost admin-only assignment grants nothing" do
    @form.form_badge_grants.create!(badge: @health_officer_badge, access: :respond)
    with_badges do
      assert FormAccess.new(person(:health_officer), person(:b1), @form).can_read?, "control: the grant works"

      @health_officer_badge.update_columns(permission: Badge.permissions[:added_by_admin_or_self])
      form = Form.find(@form.id)
      viewer = Person.find(person(:health_officer).id)
      assert_not FormAccess.new(viewer, person(:b1), form).can_read?
      assert_not FormAccess.new(viewer, person(:b1), form).can_respond?
      assert_empty form.readable_subjects_for(viewer)
      assert_empty form.respondable_subjects_for(viewer)

      sign_in viewer.user
      get results_form_path(form)
      assert_redirected_to root_path
    end
  end

  test "after its team is deleted, a team badge's form grant doesn't reach other teams" do
    @form.form_badge_grants.create!(badge: @assistant_badge, access: :read)
    with_badges do
      assert_not @form.readable_subjects_for(person(:assistant)).include?(person(:b1)), "control: Den A's badge doesn't reach Den B"

      delete_den_a
      form = Form.find(@form.id)
      viewer = Person.find(person(:assistant).id)
      assert_not form.readable_subjects_for(viewer).include?(person(:b1))
      assert_not FormAccess.new(viewer, person(:b1), form).can_read?
    end
  end

  test "after its team is deleted, a team badge's former holder doesn't see other teams on the results page" do
    @form.form_badge_grants.create!(badge: @assistant_badge, access: :read)
    with_badges do
      sign_in person(:assistant).user
      get results_form_path(@form)
      assert_response :success
      assert_not_includes response.body, "B1 World", "control: Den B isn't listed before the deletion"
      sign_out :user

      delete_den_a
      sign_in person(:assistant).user
      get results_form_path(@form)
      assert_not (response.successful? && response.body.include?("B1 World")), "Den B is listed after Den A was deleted"
      get results_form_path(@form, format: :csv)
      assert_not (response.successful? && response.body.include?("B1")), "Den B is in the CSV after Den A was deleted"
    end
  end

  test "a team-less admin badge's respond grant covers everyone the form asks" do
    coordinator = create_world_badge("Events Coordinator")
    BadgeAssignment.create!(badge: coordinator, person: person(:outsider))
    @form.form_badge_grants.create!(badge: coordinator, access: :respond)
    with_badges do
      assert_equal @form.audience.ids.sort, @form.respondable_subjects_for(person(:outsider)).ids.sort

      sign_in person(:outsider).user
      get results_form_path(@form)
      assert_select "tr#person_#{person(:b1).id} td", text: "Tacos"
      patch form_response_path(@form, person(:a2)), params: { submit: "1", form_response: { answers: { meal: "Pizza" } } }
      assert @form.response_for(person(:a2)).complete?
    end
  end
end
