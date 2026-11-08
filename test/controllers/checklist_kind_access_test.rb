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
      assert_equal "Renamed", @private.reload.label, "a rename that leaves the config alone is allowed"

      post preview_checklist_checklist_items_path(@checklist), params: { checklist_item: { kind: "private", label: "Peek" } }
      assert_response :unprocessable_entity

      assert_no_difference -> { Checklist.count } do
        post copy_checklist_path(@checklist), params: { title: "Copy", shift_months: 12 }
      end
      assert_match "You can't copy Renamed", flash[:alert]

      sign_in person(:admin).user
      post checklist_checklist_items_path(@checklist), params: { confirmed: "1", checklist_item: { kind: "private", label: "Mine" } }
      assert ChecklistItem.exists?(label: "Mine")
      assert_difference -> { Checklist.count }, 1 do
        post copy_checklist_path(@checklist), params: { title: "Copy", shift_months: 12 }
      end
    end
  end

  test "a recorded list hides capped cells and works the overall out from what the viewer sees" do
    list = ChecklistList.record!(@checklist, by: person(:admin))
    member_row = ->(viewer) { list.rows_for(viewer).find { |row| row["person_id"] == person(:member).id } }

    assert_equal "not_met", member_row.call(person(:admin))["overall"]
    assert member_row.call(person(:admin))["items"].key?(@private.id)
    managed = member_row.call(person(:club_manager))
    assert_not managed["items"].key?(@private.id)
    assert_equal "met", managed["overall"], "Login is done; the hidden item doesn't count for them"

    with_feature do
      sign_in person(:club_manager).user
      get checklist_checklist_list_path(@checklist, list)
      assert_response :success
      assert_no_match "Private value", response.body
    end
  end

  test "a group holding a capped item is capped too, in results and the preview" do
    group = add_item(@checklist, :any_of, "Cleared")
    add_item(@checklist, :private, "Private field", {}, parent: group)
    add_item(@checklist, :badge, "Safety", { badge_ids: [ @safety.id ] }, parent: group)
    refresh(@checklist)

    managed = Checklists.status_for(@checklist, [ person(:member) ], viewer: person(:club_manager))[person(:member).id]
    assert_nil managed.item(group.id)
    own = Checklists.status_for(@checklist, [ person(:member) ], viewer: person(:member))[person(:member).id]
    assert own.item(group.id)

    preview = Checklists::Preview.new(@checklist, item: group.reload, viewer: person(:club_manager))
    assert_equal 0, preview.total
    assert_equal Checklists.people_covered_by(@checklist).count, preview.hidden
  end

  test "the overall a capped viewer sees counts only the items they may see" do
    member = ->(viewer) { Checklists.status_for(@checklist, [ person(:member) ], viewer: viewer)[person(:member).id].overall }

    assert_equal "not_met", member.call(person(:admin)).status
    assert_equal "met", member.call(person(:club_manager)).status
    assert_equal "Complete", member.call(person(:club_manager)).text
  end

  test "a checklist whose only counting item is capped shows no overall to that viewer" do
    alone = create_world_checklist("Alone")
    add_rule(alone, :include, :team, team_id: @members.id)
    add_item(alone, :private, "Private")
    refresh(alone)

    assert_empty Checklists.status_for(alone, [ person(:member) ], viewer: person(:club_manager))
    assert_equal "not_met", Checklists.status_for(alone, [ person(:member) ], viewer: person(:member))[person(:member).id].overall.status
    list = ChecklistList.record!(alone, by: person(:admin))
    assert_nil list.rows_for(person(:club_manager)).find { |row| row["person_id"] == person(:member).id }["overall"]
  end

  test "an item reading another checklist is capped where that checklist's overall depends on a hidden item" do
    outer = create_world_checklist("Outer")
    add_rule(outer, :include, :team, team_id: @members.id)
    finishes = add_item(outer, :checklist, "Trip done", { checklist_id: @checklist.id })
    refresh(outer)

    assert_nil Checklists.status_for(outer, [ person(:member) ], viewer: person(:club_manager))[person(:member).id]
    assert Checklists.status_for(outer, [ person(:member) ], viewer: person(:admin))[person(:member).id].item(finishes.id)
  end

  test "impact and the rules preview count people behind a hidden item only as hidden" do
    impact = Checklists::Impact.new(@checklist, items: [ @login ], viewer: person(:club_manager))
    assert_empty impact.moves
    assert_operator impact.hidden, :>, 0
    assert_match "through an item you can't see", impact.sentences.join
    assert_match "Member World", Checklists::Impact.new(@checklist, items: [ @login ], viewer: person(:admin)).sentences.join

    preview = Checklists::Preview.new(@checklist, rules: @checklist.population_rules.to_a, viewer: person(:club_manager))
    assert_equal 0, preview.total
    assert_equal Checklists.people_covered_by(@checklist).count, preview.hidden

    with_feature do
      sign_in person(:club_manager).user
      delete checklist_checklist_item_path(@checklist, @private)
      assert_response :unprocessable_entity
      assert_no_match "Member World", response.body
      assert_match "through an item you can&#39;t see", response.body

      post preview_checklist_path(@checklist), params: { checklist_rule: { effect: "exclude", target_type: "person", person_id: person(:rookie).id } }
      assert_no_match "Member World", response.body
    end
  end

  test "the item form offers a kind's settings as narrowed for the author" do
    Checklists.register_item_kind(:narrowed, ChecklistsTestKinds::Narrowed)
    with_feature do
      sign_in person(:club_manager).user
      get new_checklist_checklist_item_path(@checklist, kind: "narrowed")
      assert_select "select[name='checklist_item[config][field]'] option[value=shirt]"
      assert_select "select[name='checklist_item[config][field]'] option[value=secret]", 0

      sign_in person(:admin).user
      get new_checklist_checklist_item_path(@checklist, kind: "narrowed")
      assert_select "select[name='checklist_item[config][field]'] option[value=secret]"
    end
  ensure
    Checklists.unregister_item_kind(:narrowed)
  end

  test "editing an item set up with a value the editor isn't offered keeps that value" do
    Checklists.register_item_kind(:narrowed, ChecklistsTestKinds::Narrowed)
    item = add_item(@checklist, :narrowed, "Secret field", { field: "secret" })
    with_feature do
      sign_in person(:club_manager).user
      get edit_checklist_checklist_item_path(@checklist, item)
      assert_select "select[name='checklist_item[config][field]'] option[value=secret][selected]", 1
      assert_select "select[name='checklist_item[config][field]'] option[value=shirt]"

      patch checklist_checklist_item_path(@checklist, item), params: { confirmed: "1", checklist_item: { label: "Renamed", config: { field: "secret" } } }
      assert_equal "Renamed", item.reload.label
      assert_equal "secret", item.config["field"]

      patch checklist_checklist_item_path(@checklist, item), params: { confirmed: "1", checklist_item: { label: "Renamed", config: { field: "shirt" } } }
      assert_response :unprocessable_entity
      assert_match "change how this item is set up", response.body
      assert_equal "secret", item.reload.config["field"], "not switched to a field they may use"

      sign_in person(:admin).user
      patch checklist_checklist_item_path(@checklist, item), params: { confirmed: "1", checklist_item: { label: "Renamed", config: { field: "shirt" } } }
      assert_equal "shirt", item.reload.config["field"]
    end
  ensure
    Checklists.unregister_item_kind(:narrowed)
  end

  test "offered settings keep saved values whatever settings_for narrows, with one or two arguments" do
    two_args = Class.new(ChecklistsTestKinds::Narrowed) do
      def self.settings_for(_author, item)
        [ Checklists::ItemKind::Setting.new(key: :field, type: :choice, label: "Field", options: item ? [] : OPTIONS) ]
      end
    end
    item = @checklist.checklist_items.new(kind: "narrowed", config: { "field" => "secret" })

    assert_equal [ [ "Shirt size", "shirt" ], [ "Secret", "secret" ] ], ChecklistsTestKinds::Narrowed.offered_settings(person(:club_manager), item).first.options
    assert_equal [ [ "Secret", "secret" ] ], two_args.offered_settings(person(:club_manager), item).first.options
  end

  test "the default batch check asks visible_to? once per person, in one query for the people" do
    ids = Checklists.people_covered_by(@checklist).ids
    visible = ChecklistsTestKinds::Private.visible_person_ids(@private, person(:member), ids)

    assert_equal [ person(:member).id ], visible
    assert_equal ids, Checklists::Kinds::Badge.visible_person_ids(@login, person(:member), ids), "kinds without a cap see everyone"
  end
end
