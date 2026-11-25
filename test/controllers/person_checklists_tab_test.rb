require "test_helper"
require_relative "../support/checklists_world"

# The Checklists tab on a profile: under the profile tabs, one card per
# checklist with the checklist's own status words, and a line when there are
# none.
class PersonChecklistsTabTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include ChecklistsWorld

  setup do
    host! "localhost"
    build_checklists_world
  end

  test "the Checklists tab shows each checklist with its status words under the profile tabs" do
    trip = create_world_checklist("Trip")
    add_rule(trip, :include, :team, team_id: @members.id)
    add_item(trip, :badge, "Safety", { badge_ids: [ @safety.id ] })
    add_item(trip, :has_login, "Login")
    refresh(trip)

    with_feature do
      sign_in person(:member).user
      get person_checklists_path(person(:member))

      assert_response :success
      assert_select ".navtab a.nav-link.active[href=?]", person_checklists_path(person(:member)), text: "Checklists"
      assert_select ".card-header h1", text: "#{person(:member).identifier_name}: Checklists"
      assert_select "##{dom_id(trip)}" do
        assert_select "a[href=?]", checklist_path(trip), text: "Trip"
        assert_select ".badge", text: Checklists::WORDS["not_met"]
      end
    end
  end

  test "the Checklists tab says so when there are none" do
    with_feature do
      sign_in person(:member).user
      get person_checklists_path(person(:member))

      assert_response :success
      assert_select ".navtab .nav-underline", 1, "under the profile tabs (the Checklists tab itself shows only when there are some)"
      assert_select "p.text-muted", text: "No checklists to show for #{person(:member).display_name}."
    end
  end
end
