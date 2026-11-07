require "test_helper"
require_relative "../support/checklists_world"
require_relative "../support/checklists_test_kinds"

# A fix link can require a policy answer, checked for the viewer when shown.
class ChecklistFixRequirementTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include ChecklistsWorld

  setup do
    host! "localhost"
    Checklists.register_item_kind(:fix_link, ChecklistsTestKinds::FixLink)
    build_checklists_world
    @checklist = create_world_checklist
    add_rule(@checklist, :include, :person, person_id: person(:member).id)
    add_item(@checklist, :fix_link, "Badge", { badge_id: @safety.id })
    refresh(@checklist)
  end

  teardown do
    Checklists.unregister_item_kind(:fix_link)
  end

  test "a group's confirm button confirms the child it came from" do
    either = add_item(@checklist, :any_of, "Either")
    add_item(@checklist, :badge, "Safety", { badge_ids: [ @safety.id ] }, parent: either)
    confirm = add_item(@checklist, :attested, "Course", { statement: "Course done", attested_by: "person" }, parent: either)
    refresh(@checklist)

    with_feature do
      sign_in person(:member).user
      get person_checklists_path(person(:member))
      action = checklist_checklist_attestations_path(@checklist, item_id: confirm.id, person_id: person(:member).id)
      assert_select "form[action=?] button", action, text: "I confirm"

      post action
    end

    assert ChecklistAttestation.exists?(person: person(:member), key: confirm.config["key"])
    assert_equal "met", evaluate(@checklist, :member, either).status
  end

  test "the link shows to a viewer whose policy allows it" do
    with_feature do
      sign_in person(:admin).user
      get person_checklists_path(person(:member))
      assert_select "a[href=?]", badge_path(@safety), text: "Edit the badge"
    end
  end

  test "others see the label as plain text" do
    with_feature do
      sign_in person(:member).user
      get person_checklists_path(person(:member))
      assert_select "a[href=?]", badge_path(@safety), 0
      assert_match "Edit the badge", response.body
    end
  end

  test "a malformed requirement never shows the link" do
    helper = Class.new { include ChecklistsHelper }.new
    assert_not helper.checklist_fix_allowed?({ "record" => @safety.to_global_id.to_s, "query" => "destroy!" })
    assert_not helper.checklist_fix_allowed?({ "record" => "gid://gatherpack/Badge/#{SecureRandom.uuid}", "query" => "update?" })
    assert helper.checklist_fix_allowed?(nil)
  end
end
