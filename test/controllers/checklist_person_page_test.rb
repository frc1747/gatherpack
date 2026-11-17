require "test_helper"
require_relative "../support/checklists_world"
require_relative "../support/checklists_test_kinds"

# A person's checklists page reads like Your Checklists: no card repeating a
# line, every button leads somewhere useful, and a kind can fill a row's
# Details its own way (ItemKind.detail_partial).
class ChecklistPersonPageTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include ChecklistsWorld

  setup do
    host! "localhost"
    @view_paths = PersonChecklistsController.view_paths
    PersonChecklistsController.prepend_view_path(ChecklistsTestKinds::Shifts::VIEWS)
    Checklists.register_item_kind(:shifts, ChecklistsTestKinds::Shifts)
    Checklists.register_item_kind(:progress, ChecklistsTestKinds::Progress)
    build_checklists_world

    # Trip: two items, keeps its card. Concessions: one counted item with
    # its own Details and a next step, shown as a line on Travel.
    @trip = create_world_checklist("Trip")
    add_rule(@trip, :include, :team, team_id: @members.id)
    add_item(@trip, :badge, "Safety", { badge_ids: [ @safety.id ] })
    add_item(@trip, :has_login, "Login")
    @concessions = create_world_checklist("Concessions")
    add_rule(@concessions, :include, :team, team_id: @members.id)
    add_item(@concessions, :shifts, "Shifts", { confirmed: "1", owed: "2" })
    @travel = create_world_checklist("Travel")
    add_rule(@travel, :include, :team, team_id: @members.id)
    @concessions_line = add_item(@travel, :checklist, "Concessions", { checklist_id: @concessions.id })
    @trip_line = add_item(@travel, :checklist, "Trip", { checklist_id: @trip.id })
    [ @trip, @concessions, @travel ].each { |checklist| refresh(checklist) }
  end

  teardown do
    Checklists.unregister_item_kind(:shifts)
    Checklists.unregister_item_kind(:progress)
    PersonChecklistsController.view_paths = @view_paths
  end

  test "a one-item checklist another shows as a line has no card; one with several items keeps its card" do
    with_feature do
      sign_in person(:member).user
      get person_checklists_path(person(:member))

      assert_response :success
      assert_select "##{dom_id(@travel)}"
      assert_select "##{dom_id(@trip)}", 1, "several items keep their card"
      assert_select "##{dom_id(@concessions)}", false, "its one item is already Travel's Concessions line"
    end
  end

  test "Checklists.without_repeats judges by what the viewer sees of each line" do
    results = Checklists.checklist_for(person(:member), viewer: person(:member))
    assert_equal %w[Travel Trip], Checklists.without_repeats(results).map { |checklist, _| checklist.title }.sort

    @travel.checklist_items.where(kind: "checklist").destroy_all
    refresh(@travel)
    results = Checklists.checklist_for(person(:member), viewer: person(:member))
    assert_includes Checklists.without_repeats(results).map { |checklist, _| checklist.title }, "Concessions", "no line shows it, so it keeps its card"
  end

  test "a line passing counts through takes the counted item's fix; any other leads to the checklist's card on the person's page" do
    assert_equal({ "label" => "Next: Stocking", "path" => "/shifts/next", "by" => "person" }, evaluate(@travel, :member, @concessions_line).fix)
    fix = evaluate(@travel, :member, @trip_line).fix
    assert_equal "See Trip", fix["label"]
    assert_equal person_checklists_path(person(:member), anchor: dom_id(@trip)), fix["path"]

    with_feature do
      sign_in person(:member).user
      get person_checklists_path(person(:member))

      assert_select "##{dom_id(@travel)} a[href='/shifts/next']", text: "Next: Stocking"
      assert_select "##{dom_id(@travel)} a[href=?]", person_checklists_path(person(:member), anchor: dom_id(@trip)), text: "See Trip"
      assert_select "##{dom_id(@travel)} .list-group-item a[href=?]", checklist_path(@trip), false, "never the checklist's report"
    end
  end

  test "a line passing a confirm through confirms on the counted item's checklist" do
    waiver = create_world_checklist("Waiver")
    add_rule(waiver, :include, :team, team_id: @members.id)
    signed = add_item(waiver, :attested, "Signed", { statement: "Waiver signed", attested_by: "person" })
    line = add_item(@travel, :checklist, "Waiver", { checklist_id: waiver.id })
    refresh(waiver)
    refresh(@travel)

    fix = evaluate(@travel, :member, line).fix
    assert_equal "attest", fix["action"]
    assert_equal [ signed.id, waiver.id ], fix.values_at("item_id", "checklist_id")
  end

  test "a leader-only pointer is hidden from the member and shown to an organizer" do
    with_feature do
      sign_in person(:member).user
      get person_checklists_path(person(:member))
      assert_response :success
      assert_select "##{dom_id(@trip)}", text: /Safety/
      assert_no_match "Ask a leader", response.body

      sign_in person(:club_manager).user
      get person_checklists_path(person(:member))
      assert_response :success
      assert_match "Ask a leader", response.body
    end
  end

  test "a kind with a detail partial fills Details, also through a passing line; one without keeps its detail lines" do
    add_item(@trip, :progress, "Hours", { confirmed: "1", owed: "3" })
    refresh(@trip)
    with_feature do
      sign_in person(:parent).user
      get person_checklists_path(person(:kid))
      assert_response :success

      assert_select "##{dom_id(@travel)} details .test-shifts-detail", text: "1 shifts for Kid, seen by Parent"
      assert_select "##{dom_id(@trip)} details li", text: "1 of 3"
      assert_select "##{dom_id(@trip)} .test-shifts-detail", false
    end
  end

  private

  def dom_id(record, prefix = nil)
    ActionView::RecordIdentifier.dom_id(record, prefix)
  end
end
