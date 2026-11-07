require "test_helper"
require_relative "../support/checklists_world"
require_relative "../support/checklists_test_kinds"

# A kind can cap a result at "status only": the status shows where the
# core allows it, its summary, detail, measures and fix don't.
class ChecklistStatusCapTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include ChecklistsWorld

  setup do
    host! "localhost"
    Checklists.register_item_kind(:hours, ChecklistsTestKinds::StatusOnly)
    Checklists.register_item_kind(:batch_hours, ChecklistsTestKinds::BatchStatusOnly)
    Checklists.register_item_kind(:private, ChecklistsTestKinds::Private)
    build_checklists_world
    @checklist = create_world_checklist
    add_rule(@checklist, :include, :team, team_id: @members.id)
    @hours = add_item(@checklist, :hours, "Hours")
    refresh(@checklist)
  end

  teardown do
    %i[hours batch_hours private].each { |kind| Checklists.unregister_item_kind(kind) }
  end

  test "a manager sees the status but not the numbers; the person and admins see everything" do
    entry = ->(viewer) { Checklists.status_for(@checklist, [ person(:member) ], viewer: viewer)[person(:member).id].item(@hours.id) }

    managed = entry.call(person(:club_manager))
    assert_equal :status, managed.access
    assert_equal "not_met", managed.status
    assert_equal "Not yet", managed.text
    assert_nil managed.summary
    assert_nil managed.detail
    assert_nil managed.measures

    assert_equal "12 of 20 hours", entry.call(person(:member)).summary
    assert_equal({ "hours" => 12 }, entry.call(person(:admin)).measures)
  end

  test "a status-only item still counts in the overall, which stays as stored" do
    overall = Checklists.status_for(@checklist, [ person(:member) ], viewer: person(:club_manager))[person(:member).id].overall

    assert_equal "not_met", overall.status
  end

  test "a group takes the strictest cap of the items inside it" do
    group = add_item(@checklist, :any_of, "Either")
    add_item(@checklist, :hours, "Hours", {}, parent: group)
    add_item(@checklist, :has_login, "Login", {}, parent: group)
    hidden_group = add_item(@checklist, :any_of, "Hidden")
    add_item(@checklist, :hours, "Hours", {}, parent: hidden_group)
    add_item(@checklist, :private, "Private", {}, parent: hidden_group)
    refresh(@checklist)

    assert_equal({ person(:member).id => :status }, Checklists.cap_levels(group.reload, person(:club_manager), [ person(:member).id ]))
    status = Checklists.status_for(@checklist, [ person(:member) ], viewer: person(:club_manager))[person(:member).id]
    assert_equal :status, status.item(group.id).access
    assert_nil status.item(group.id).summary
    assert_nil status.item(hidden_group.id), "hidden when any item inside hides it"
  end

  test "a kind can answer the cap in batch" do
    batch = add_item(@checklist, :batch_hours, "Batch")
    refresh(@checklist)

    assert_equal [ person(:member).id ], ChecklistsTestKinds::BatchStatusOnly.visible_person_ids(batch, person(:club_manager), [ person(:member).id ])
    entry = Checklists.status_for(@checklist, [ person(:member) ], viewer: person(:club_manager))[person(:member).id].item(batch.id)
    assert_equal :status, entry.access
    assert_nil entry.summary
  end

  test "the report and the person page show the status without the numbers" do
    with_feature do
      sign_in person(:club_manager).user
      get checklist_path(@checklist)
      assert_response :success
      assert_match "Not yet", response.body
      assert_no_match "12 of 20 hours", response.body
      assert_no_match "&quot;hours&quot;", response.body

      get person_checklists_path(person(:member))
      assert_no_match "12 of 20 hours", response.body
      assert_no_match "Short by 8 hours", response.body

      sign_in person(:member).user
      get person_checklists_path(person(:member))
      assert_match "Short by 8 hours", response.body
    end
  end

  test "a recorded list drops the summary of a status-only cell" do
    list = ChecklistList.record!(@checklist, by: person(:admin))
    cell = ->(viewer) { list.rows_for(viewer).find { |row| row["person_id"] == person(:member).id }["items"][@hours.id] }

    assert_equal "not_met", cell.call(person(:club_manager))["status"]
    assert_nil cell.call(person(:club_manager))["summary"]
    assert_equal "12 of 20 hours", cell.call(person(:admin))["summary"]
  end
end
