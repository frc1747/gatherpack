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
      assert_redirected_to edit_checklist_path(@checklist, anchor: "access")
      assert_equal "You can't grant access to Guarded; ask someone who can.", flash[:alert]

      assert_no_difference -> { ChecklistGrant.count } do
        post checklist_checklist_grants_path(@checklist), params: { checklist_grant: { team_id: @crew.id, access: "full", item_ids: [ @group.id ] } }
      end
      assert_match "can't grant access to Guarded", flash[:alert], "a group holding the item is covered too"

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

  test "a grant doesn't show an item added under its group that its maker couldn't have granted" do
    other_group = add_item(@checklist, :any_of, "Other")
    login_inside = add_item(@checklist, :has_login, "Login inside", parent: other_group)
    @checklist.checklist_grants.create!(team: @crew, access: :full, item_ids: [ other_group.id ], created_by: person(:organizer))
    moved = add_item(@checklist, :grant_guarded, "Added later", parent: other_group)
    @guarded.update!(parent: other_group)

    crewmate = create_world_person("Crewmate", @crew)
    visibility = Checklists::Visibility.new(@checklist, crewmate)
    assert_equal :full, visibility.access(login_inside, person(:member).id)
    assert_nil visibility.access(moved, person(:member).id), "an item added under the granted group"
    assert_nil visibility.access(@guarded, person(:member).id), "an item moved under the granted group"
    assert_nil visibility.access(other_group, person(:member).id), "the group, whose result tells of the item"

    @checklist.checklist_grants.create!(team: @crew, access: :full, item_ids: [ other_group.id ], created_by: person(:admin))
    by_admin = Checklists::Visibility.new(@checklist, crewmate)
    assert_equal :full, by_admin.access(moved, person(:member).id), "an admin's grant still counts"
    assert_equal :full, by_admin.access(other_group, person(:member).id)
  end

  test "a grant doesn't show a group with a refusing item further down" do
    outer = add_item(@checklist, :any_of, "Outer")
    inner = add_item(@checklist, :any_of, "Inner", parent: outer)
    @guarded.update!(parent: inner)
    @checklist.checklist_grants.create!(team: @crew, access: :full, item_ids: [ outer.id ], created_by: person(:organizer))

    visibility = Checklists::Visibility.new(@checklist, create_world_person("Crewmate", @crew))
    assert_nil visibility.access(inner, person(:member).id)
    assert_nil visibility.access(outer, person(:member).id)
  end

  test "copied items are checked against the copy's population" do
    Checklists.register_item_kind(:no_applicants, ChecklistsTestKinds::NoApplicants)
    @checklist.checklist_grants.destroy_all
    add_rule(@checklist, :include, :applicants, team_id: @joiners.id)
    add_item(@checklist, :no_applicants, "Members only")

    with_organizers do
      sign_in person(:organizer).user
      assert_no_difference "Checklist.count" do
        post copy_checklist_path(@checklist), params: { title: "Copy", shift_months: 12 }
      end
      assert_equal "You can't copy Members only: ask someone who can set those items up.", flash[:alert]
    end
  ensure
    Checklists.unregister_item_kind(:no_applicants)
  end

  test "kinds that don't limit grants honour every grant, including ones with no maker" do
    grant = @checklist.checklist_grants.create!(team: @crew, access: :full, item_ids: [ @login.id ])
    assert Checklists::Kinds::HasLogin.honours_grant?(@login, grant)
    assert_equal :full, Checklists::Visibility.new(@checklist, create_world_person("Crewmate", @crew)).access(@login, person(:member).id)
  end

  test "copying is refused when the copier couldn't make a copied grant, and a copied grant is made by whoever copies" do
    @checklist.checklist_grants.create!(team: @crew, access: :full, item_ids: [ @guarded.id ], created_by: person(:admin))
    with_organizers do
      sign_in person(:organizer).user
      assert_no_difference -> { Checklist.count } do
        post copy_checklist_path(@checklist), params: { title: "Copy", shift_months: 12 }
      end
      assert_redirected_to copy_checklist_path(@checklist)
      assert_equal "You can't copy Crew members' full access to Guarded: ask someone who can grant it.", flash[:alert]

      sign_in person(:admin).user
      post copy_checklist_path(@checklist), params: { title: "Copy", shift_months: 12 }
      assert_equal person(:admin), Checklist.find_by!(title: "Copy").checklist_grants.sole.created_by
    end
  end

  test "copying checks each copied item against the copier, replacements included, before saving anything" do
    Checklists.register_item_kind(:restricted_badges, ChecklistsTestKinds::RestrictedBadges)
    @checklist.checklist_grants.destroy_all
    open_badge = create_world_badge("Helpers 2026")
    restricted = create_world_badge("Restricted 2027")
    add_item(@checklist, :restricted_badges, "Named badge", { "badge_ids" => [ open_badge.id ] })

    with_organizers do
      sign_in person(:organizer).user
      assert_no_difference [ "Checklist.count", "ChecklistItem.count" ] do
        post copy_checklist_path(@checklist), params: { title: "Copy", shift_months: 12, replace: { "Badge:#{open_badge.id}" => restricted.id } }
      end
      assert_equal "You can't copy Named badge: ask someone who can set those items up.", flash[:alert]

      post copy_checklist_path(@checklist), params: { title: "Copy", shift_months: 12 }
      copy = Checklist.find_by!(title: "Copy")
      assert_equal [ open_badge.id ], copy.checklist_items.find_by!(label: "Named badge").config["badge_ids"]
    end
  ensure
    Checklists.unregister_item_kind(:restricted_badges)
  end

  test "the Add item menu lists only kinds the person may set up" do
    with_organizers do
      sign_in person(:organizer).user
      get edit_checklist_path(@checklist)
      assert_response :success
      assert_select ".dropdown-menu a[href*='kind=has_login']"
      assert_select ".dropdown-menu a[href*='kind=private']", 0

      sign_in person(:admin).user
      get edit_checklist_path(@checklist)
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
