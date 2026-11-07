require "test_helper"
require_relative "../support/checklists_world"
require_relative "../support/checklists_test_kinds"

# A kind can cap who sees a person's result (ItemKind.visible_to?) and who
# may set an item up (ItemKind.authorable_by?), on top of everything else.
class ChecklistKindAccessTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include ChecklistsWorld

  setup do
    host! "localhost"
    Checklists.register_item_kind(:private, ChecklistsTestKinds::Private)
    build_checklists_world
    @checklist = create_world_checklist
    add_rule(@checklist, :include, :team, team_id: @members.id)
    @login = add_item(@checklist, :has_login, "Login")
    @private = add_item(@checklist, :private, "Private")
    refresh(@checklist)
  end

  teardown do
    Checklists.unregister_item_kind(:private)
  end

  test "the cap applies to a manager with full access, and the person still sees their own" do
    statuses = Checklists.status_for(@checklist, [ person(:member) ], viewer: person(:club_manager))
    status = statuses[person(:member).id]

    assert_nil status.item(@private.id)
    assert status.item(@login.id)
    assert_nil status.overall.summary, "the hidden unmet item isn't counted"
    assert_equal({ "unmet" => 0 }, status.overall.measures)

    own = Checklists.status_for(@checklist, [ person(:member) ], viewer: person(:member))[person(:member).id]
    assert_equal "Private value", own.item(@private.id).summary
    assert Checklists.status_for(@checklist, [ person(:member) ], viewer: person(:admin))[person(:member).id].item(@private.id)
  end

  test "a grant for the item doesn't get past the cap" do
    @checklist.checklist_grants.create!(badge: @viewer_badge, item_ids: [ @private.id ], access: :full)
    give_badge(:outsider, @viewer_badge)

    status = Checklists.status_for(@checklist, [ person(:member) ], viewer: person(:outsider))[person(:member).id]
    assert status, "the grant still shows the overall"
    assert_nil status.item(@private.id)
  end

  test "the report, its sort and filter data, and the person page leave the capped value out" do
    with_feature do
      sign_in person(:club_manager).user
      get checklist_path(@checklist)
      assert_response :success
      assert_no_match "Private value", response.body
      assert_no_match "&quot;unmet&quot;:1", response.body
      assert_select "input[data-checklist-report-target=tick][data-column='3']", 0

      get person_checklists_path(person(:member))
      assert_no_match "Private value", response.body

      sign_in person(:member).user
      get person_checklists_path(person(:member))
      assert_match "Private value", response.body
    end
  end

  test "the preview counts capped people only as hidden" do
    preview = Checklists::Preview.new(@checklist, item: @private, viewer: person(:club_manager))
    covered = Checklists.people_covered_by(@checklist).count

    assert_equal covered, preview.hidden
    assert_equal 0, preview.total
    assert_equal covered, Checklists::Preview.new(@checklist, item: @private, viewer: person(:admin)).total
  end

  test "only an allowed author can create, edit, preview or copy the item" do
    with_feature do
      sign_in person(:club_manager).user
      post checklist_checklist_items_path(@checklist), params: { confirmed: "1", checklist_item: { kind: "private", label: "Mine" } }
      assert_response :unprocessable_entity
      assert_match "set up this item this way", response.body
      assert_not ChecklistItem.exists?(label: "Mine")

      patch checklist_checklist_item_path(@checklist, @private), params: { confirmed: "1", checklist_item: { label: "Renamed" } }
      assert_response :unprocessable_entity
      assert_equal "Private", @private.reload.label

      post preview_checklist_checklist_items_path(@checklist), params: { checklist_item: { kind: "private", label: "Peek" } }
      assert_response :unprocessable_entity

      assert_no_difference -> { Checklist.count } do
        post copy_checklist_path(@checklist), params: { title: "Copy", shift_months: 12 }
      end
      assert_match "You can't copy Private", flash[:alert]

      sign_in person(:admin).user
      post checklist_checklist_items_path(@checklist), params: { confirmed: "1", checklist_item: { kind: "private", label: "Mine" } }
      assert ChecklistItem.exists?(label: "Mine")
      assert_difference -> { Checklist.count }, 1 do
        post copy_checklist_path(@checklist), params: { title: "Copy", shift_months: 12 }
      end
    end
  end

  test "the default batch check asks visible_to? once per person, in one query for the people" do
    ids = Checklists.people_covered_by(@checklist).ids
    visible = ChecklistsTestKinds::Private.visible_person_ids(@private, person(:member), ids)

    assert_equal [ person(:member).id ], visible
    assert_equal ids, Checklists::Kinds::Badge.visible_person_ids(@login, person(:member), ids), "kinds without a cap see everyone"
  end
end
