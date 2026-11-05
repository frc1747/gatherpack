require "test_helper"
require_relative "../support/commitments_world"

class PersonCommitmentsTabTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include CommitmentsWorld

  setup do
    travel_to Time.zone.parse("2026-10-20 12:00")
    host! "localhost"
    build_commitments_world
    @commitment = create_world_commitment(group_relationship_type: @parent_of)
  end

  test "a person sees their own tab, active on the commitments page" do
    with_feature do
      sign_in person(:member).user

      get person_path(person(:member))
      assert_select "a.nav-link:not(.active)[href=?]", person_commitments_path(person(:member)), text: "Commitments"

      get person_commitments_path(person(:member))
      assert_response :success
      assert_select "a.nav-link.active[href=?]", person_commitments_path(person(:member)), text: "Commitments"
    end
  end

  test "a parent related through the grouping relationship sees the tab on the child's profile" do
    with_feature do
      sign_in person(:organizer).user

      get person_path(person(:kid))
      assert_select "a.nav-link[href=?]", person_commitments_path(person(:kid)), text: "Commitments"
    end
  end

  test "an unrelated member doesn't see the tab on someone else's profile" do
    with_feature do
      sign_in person(:member2).user

      get person_path(person(:kid))
      assert_response :success
      assert_select "a.nav-link", text: "Commitments", count: 0
    end
  end

  test "no tab when the viewer sees no commitments" do
    @commitment.destroy!
    with_feature do
      sign_in person(:member2).user

      get person_path(person(:kid))
      assert_select "a.nav-link", text: "Commitments", count: 0
      get person_path(person(:member2))
      assert_select "a.nav-link", text: "Commitments", count: 0
    end
  end

  test "no tab while the feature is off" do
    sign_in person(:member).user

    get person_path(person(:member))
    assert_response :success
    assert_select "a.nav-link", text: "Commitments", count: 0
  end
end
