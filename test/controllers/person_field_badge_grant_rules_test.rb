require "test_helper"
require_relative "../support/person_fields_world"
require_relative "../support/settings_test_helper"

# A badge grants person field access only while admins choose its holders
# and, for a team badge, while its team exists.
class PersonFieldBadgeGrantRulesTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include PersonFieldsWorld
  include SettingsTestHelper

  setup do
    host! "localhost"
    build_person_fields_world
    @medical = create_world_field("Medical Notes", read: "guardians", write: "admin")
    person(:a1).set_field_value(@medical, "epilepsy, rescue meds in bag")
    person(:b1).set_field_value(@medical, "asthma, inhaler in bag")
  end

  test "a badge that grants field access can't be made self-assignable while the grant stands" do
    @medical.person_field_badge_grants.create!(badge: @health_officer_badge, access: :read)

    sign_in person(:admin).user
    patch badge_path(@health_officer_badge), params: { badge: { permission: "added_by_admin_or_self" } }

    assert_response :unprocessable_entity
    assert @health_officer_badge.reload.added_by_admin?
    assert_includes response.body, "Remove this badge&#39;s access grants"
  end

  test "a student can't self-assign a granting badge into the field" do
    @medical.person_field_badge_grants.create!(badge: @health_officer_badge, access: :read)
    sign_in person(:admin).user
    patch badge_path(@health_officer_badge), params: { badge: { permission: "added_by_admin_or_self" } }
    sign_out :user

    with_settings(feature_person_fields: "true") do
      sign_in person(:b1).user
      post badge_badge_assignments_path(@health_officer_badge), params: { badge_assignment: { person_id: person(:b1).id } }
      get person_path(person(:a1))
      assert_not_includes response.body, "epilepsy"
    end
  end

  test "a badge whose grants were removed can be made self-assignable" do
    grant = @medical.person_field_badge_grants.create!(badge: @health_officer_badge, access: :read)
    grant.destroy!

    sign_in person(:admin).user
    patch badge_path(@health_officer_badge), params: { badge: { permission: "added_by_admin_or_self" } }

    assert @health_officer_badge.reload.added_by_admin_or_self?
  end

  test "a grant from a badge that lost admin-only assignment grants nothing" do
    grant = @medical.person_field_badge_grants.create!(badge: @health_officer_badge, access: :read)
    @health_officer_badge.update_columns(permission: Badge.permissions[:added_by_admin_or_self])
    viewer = person(:health_officer)

    assert_not PersonFieldAccess.new(viewer, person(:a1)).readable?(PersonField.find(@medical.id))
    assert_not_includes PersonField.find(@medical.id).readable_subjects_for(viewer), person(:a1)
    assert_not grant.reload.badge.grant_effective?
  end

  test "an org-wide admin badge still grants the field to everyone" do
    @medical.person_field_badge_grants.create!(badge: @health_officer_badge, access: :read)
    viewer = person(:health_officer)
    field = PersonField.find(@medical.id)

    assert PersonFieldAccess.new(viewer, person(:b1)).readable?(field)
    assert PersonFieldAccess.new(viewer, person(:outsider)).readable?(field)
    assert_includes field.readable_subjects_for(viewer), person(:b1)
    assert_includes field.readable_subjects_for(viewer), person(:outsider)
  end

  test "a team badge grants the field within its team only" do
    @medical.person_field_badge_grants.create!(badge: @assistant_badge, access: :read)
    viewer = person(:assistant)
    field = PersonField.find(@medical.id)

    assert PersonFieldAccess.new(viewer, person(:a1)).readable?(field)
    assert_includes field.readable_subjects_for(viewer), person(:a1)
    assert_not PersonFieldAccess.new(viewer, person(:b1)).readable?(field)
    assert_not_includes field.readable_subjects_for(viewer), person(:b1)
  end

  test "after its team is deleted, a team badge grants the field to nobody" do
    @medical.person_field_badge_grants.create!(badge: @assistant_badge, access: :read)
    delete_den_a_as_pack_leader
    viewer = person(:assistant).reload
    field = PersonField.find(@medical.id)

    assert_not_includes field.readable_subjects_for(viewer), person(:b1)
    assert_not_includes field.readable_subjects_for(viewer), person(:outsider)
    assert_not PersonFieldAccess.new(viewer, person(:b1)).readable?(field)
    assert_not PersonFieldAccess.new(viewer, person(:outsider)).readable?(field)
  end

  test "after its team is deleted, a team badge shows no birthdays on the calendar" do
    PersonField.ensure_system_fields!
    Membership.create!(person: person(:assistant), team: @pack)
    birthday = PersonField.system.find_by!(system_source: "birthday")
    birthday.update!(read_permission: "family", write_permission: "family")
    birthday.person_field_badge_grants.create!(badge: @assistant_badge, access: :read)
    person(:b1).update_columns(birthday: Date.new(2012, 5, 17))

    with_settings(feature_person_fields: "true") do
      sign_in person(:assistant).user
      get_birthdays
      assert_response :success
      assert_not_includes response.body, "B1 World"
      sign_out :user

      delete_den_a_as_pack_leader

      sign_in person(:assistant).user
      get_birthdays
      assert_response :success
      assert_not_includes response.body, "B1 World"
    end
  end

  test "badges count as granting only while admin-assigned and their team exists" do
    gone = Team.create!(name: "Gone", team_type: team_types(:one))
    orphan = Badge.create!(name: "Orphan", short: "Orp", color: "#336699", badge_type: badge_types(:one), team: gone, permission: :added_by_admin)
    self_added = Badge.create!(name: "Self", short: "Sel", color: "#336699", badge_type: badge_types(:one), permission: :added_by_admin_or_self)
    gone.delete

    effective = Badge.grant_effective
    assert_includes effective, @health_officer_badge
    assert_includes effective, @assistant_badge
    assert_not_includes effective, orphan
    assert_not_includes effective, self_added
    assert @health_officer_badge.grant_effective?
    assert @assistant_badge.grant_effective?
    assert_not orphan.reload.grant_effective?
    assert_not self_added.grant_effective?
  end

  private

  def delete_den_a_as_pack_leader
    sign_in person(:pack_leader).user
    delete team_path(@den_a)
    sign_out :user
    assert_not Team.exists?(@den_a.id)
    assert BadgeAssignment.exists?(badge: @assistant_badge, person: person(:assistant))
  end

  def get_birthdays
    get "/calendar/calendar.json", params: { birthdays: "1", start_time: "2026-05-01", end_time: "2026-06-01", q: { name_i_cont: "" } }
  end
end
