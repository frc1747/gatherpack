require "test_helper"
require_relative "../support/forms_world"
require_relative "../support/settings_test_helper"

# A team badge can only be given to someone in its team. Once its holder
# leaves that team the badge is taken away, so it stops granting anything.
class TeamBadgeAfterLeavingTeamTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include FormsWorld
  include SettingsTestHelper

  setup do
    host! "localhost"
    build_person_fields_world
    # The assistant's Den A badge grants read access to Den A's medical field.
    @medical = create_world_field("Medical Notes", read: "guardians", write: "admin")
    @medical.person_field_badge_grants.create!(badge: @assistant_badge, access: :read)
    person(:a1).set_field_value(@medical, "epilepsy, rescue meds in bag")

    # The assistant moves from Den A to Den B.
    Membership.create!(person: person(:assistant), team: @den_b)
    Membership.find_by!(person: person(:assistant), team: @den_a).destroy!
  end

  test "a former Den A assistant no longer reads Den A's medical field on a profile" do
    with_settings(feature_person_fields: "true") do
      sign_in person(:assistant).user
      get person_path(person(:a1))
      assert_response :success
      assert_not response.body.include?("epilepsy"),
        "the assistant left Den A but their Den A badge still grants the medical field"
    end
  end

  test "a former Den A assistant no longer reads Den A responses through a form badge grant" do
    form = create_world_form
    form.form_badge_grants.create!(badge: @assistant_badge, access: :read)
    assert_not FormAccess.new(person(:assistant), person(:a1), form).can_read?,
      "the assistant left Den A but their Den A badge still grants read on A1's form response"
  end

  test "leaving the team takes the team badge away" do
    assert_not BadgeAssignment.exists?(badge: @assistant_badge, person: person(:assistant))
  end
end
