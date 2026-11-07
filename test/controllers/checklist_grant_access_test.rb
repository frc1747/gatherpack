require "test_helper"
require_relative "../support/checklists_world"
require_relative "../support/checklists_test_kinds"

# A kind can refuse a grant covering it (ItemKind.grantable_by?), grants
# keep who made them (ItemKind.honours_grant?), and the "Add item" menu
# offers only kinds the person may set up (ItemKind.authorable_by?).
class ChecklistGrantAccessTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include ChecklistsWorld

  setup do
    host! "localhost"
    Checklists.register_item_kind(:grant_guarded, ChecklistsTestKinds::GrantGuarded)
    Checklists.register_item_kind(:private, ChecklistsTestKinds::Private)
    build_checklists_world
    @checklist = create_world_checklist
    add_rule(@checklist, :include, :team, team_id: @members.id)
    @group = add_item(@checklist, :any_of, "Either")
    @guarded = add_item(@checklist, :grant_guarded, "Guarded", parent: @group)
    @login = add_item(@checklist, :has_login, "Login")
  end

  teardown do
    Checklists.unregister_item_kind(:grant_guarded)
    Checklists.unregister_item_kind(:private)
  end

  test "an organizer who isn't a manager can't make a full grant covering a kind that refuses it" do
    with_organizers do
      sign_in person(:organizer).user
      assert_no_difference -> { ChecklistGrant.count } do
        post checklist_checklist_grants_path(@checklist), params: { checklist_grant: { team_id: @crew.id, access: "full", item_ids: [ @guarded.id ] } }
      end
      assert_response :unprocessable_entity
      assert_equal "You can't grant access to Guarded; ask someone who can.", response.body

      assert_no_difference -> { ChecklistGrant.count } do
        post checklist_checklist_grants_path(@checklist), params: { checklist_grant: { team_id: @crew.id, access: "full", item_ids: [ @group.id ] } }
      end
      assert_response :unprocessable_entity, "a group holding the item is covered too"

      post checklist_checklist_grants_path(@checklist), params: { checklist_grant: { team_id: @crew.id, access: "status", item_ids: [ @guarded.id ] } }
      assert_response :see_other
      post checklist_checklist_grants_path(@checklist), params: { checklist_grant: { team_id: @crew.id, access: "full", item_ids: [ @login.id ] } }
      assert_response :see_other
      assert_equal [ person(:organizer) ], @checklist.checklist_grants.map(&:created_by).uniq
    end
  end

  test "an admin's full grant is allowed, and the kind can tell who made a grant" do
    with_organizers do
      sign_in person(:admin).user
      post checklist_checklist_grants_path(@checklist), params: { checklist_grant: { team_id: @crew.id, access: "full", item_ids: [ @guarded.id ] } }
      assert_response :see_other
    end

    by_admin = @checklist.checklist_grants.sole
    assert_equal person(:admin), by_admin.created_by
    assert ChecklistsTestKinds::GrantGuarded.honours_grant?(@guarded, by_admin)

    by_organizer = @checklist.checklist_grants.create!(team: @crew, access: :full, item_ids: [ @guarded.id ], created_by: person(:organizer))
    assert_not ChecklistsTestKinds::GrantGuarded.honours_grant?(@guarded, by_organizer)
    unknown = @checklist.checklist_grants.create!(team: @crew, access: :status, item_ids: [ @guarded.id ])
    assert_not ChecklistsTestKinds::GrantGuarded.honours_grant?(@guarded, unknown), "a grant with no maker isn't honoured"
  end

  test "a copied grant is made by whoever copies" do
    with_organizers do
      @checklist.checklist_grants.create!(team: @crew, access: :full, item_ids: [ @guarded.id ], created_by: person(:admin))
      copy = Checklists::Copier.new(@checklist).call(title: "Copy", by: person(:organizer))

      assert_equal person(:organizer), copy.checklist_grants.sole.created_by
    end
  end

  test "the Add item menu lists only kinds the person may set up" do
    with_organizers do
      sign_in person(:organizer).user
      get checklist_path(@checklist)
      assert_response :success
      assert_select ".dropdown-menu a[href*='kind=has_login']"
      assert_select ".dropdown-menu a[href*='kind=private']", 0

      sign_in person(:admin).user
      get checklist_path(@checklist)
      assert_select ".dropdown-menu a[href*='kind=private']"
    end
  end

  private

  def with_organizers(&block)
    with_settings(feature_checklists: "true", checklists_organizers: "Checklist Organizer > Club") do
      @checklist.checklist_organizers.create!(person: person(:organizer))
      block.call
    end
  end
end
