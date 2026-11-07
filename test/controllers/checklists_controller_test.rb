require "test_helper"
require_relative "../support/checklists_world"
require_relative "../support/checklists_test_kinds"

class ChecklistsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include ChecklistsWorld

  setup do
    host! "localhost"
    build_checklists_world
    @checklist = create_world_checklist("Trip")
    add_rule(@checklist, :include, :team, team_id: @members.id)
    @safety_item = add_item(@checklist, :badge, "Safety", { badge_ids: [ @safety.id ] })
    @login_item = add_item(@checklist, :has_login, "Login", {}, read_level: "self_and_leaders")
    give_badge(:member, @safety)
    refresh(@checklist)
  end

  # Flag off

  test "with the feature off every checklist page sends people away" do
    sign_in person(:admin).user
    [ checklists_path, checklist_path(@checklist), new_checklist_path, edit_checklist_path(@checklist), copy_checklist_path(@checklist),
      new_checklist_checklist_item_path(@checklist, kind: "badge"), person_checklists_path(person(:member)) ].each do |path|
      get path
      assert_redirected_to root_path, path
    end
    post checklists_path, params: { checklist: { title: "Nope", team_id: @club.id } }
    assert_redirected_to root_path
    assert_not Checklist.exists?(title: "Nope")
  end

  test "with the feature off there's no sidebar item" do
    sign_in person(:admin).user
    get root_path
    assert_no_match "Checklists", response.body

    with_feature do
      get root_path
      assert_match ">Checklists<", response.body.gsub(/\s+/, "")
    end
  end

  # Visibility tiers (spec §14.5)

  test "an admin and a manager of the checklist's team see everyone and every item" do
    with_feature do
      [ :admin, :club_manager ].each do |viewer|
        sign_in person(viewer).user
        get checklist_path(@checklist)
        assert_response :success
        assert_match "MemberTwo World", response.body
        assert_match "Login", response.body
        assert_match "Setup", response.body
      end
    end
  end

  test "a member sees only themselves" do
    with_feature do
      sign_in person(:member).user
      get checklist_path(@checklist)

      assert_response :success
      assert_match "Member World", response.body
      assert_no_match "MemberTwo World", response.body
      assert_no_match "Kid World", response.body
      assert_no_match "Setup", response.body
    end
  end

  test "a guardian sees their ward, but not an item for the person and leaders only" do
    with_feature do
      sign_in person(:parent).user
      get checklist_path(@checklist)

      assert_response :success
      assert_match "Kid World", response.body
      assert_no_match "Member World", response.body
      assert_no_match ">Login<", response.body.gsub(/\s+/, "")
    end
  end

  test "someone it doesn't cover and with no grant gets nothing" do
    with_feature do
      sign_in person(:outsider).user
      get checklist_path(@checklist)
      assert_response :not_found

      get checklists_path
      assert_no_match "Trip", response.body
    end
  end

  test "a team grant shows everyone's overall and the granted item, nothing more" do
    @checklist.checklist_grants.create!(team: @crew, item_ids: [ @safety_item.id ], access: :status)
    with_feature do
      sign_in person(:organizer).user
      get checklist_path(@checklist)

      assert_response :success
      assert_match "MemberTwo World", response.body
      assert_match "Safety", response.body
      assert_no_match ">Login<", response.body.gsub(/\s+/, "")
      assert_no_match "Holds Safety", response.body, "status only, no summary"
    end
  end

  test "a badge grant at full level shows summaries" do
    @checklist.checklist_grants.create!(badge: @viewer_badge, item_ids: [ @safety_item.id ], access: :full)
    give_badge(:outsider, @viewer_badge)
    with_feature do
      sign_in person(:outsider).user
      get checklist_path(@checklist)

      assert_response :success
      assert_match "Holds Safety 2026", response.body
    end
  end

  test "status_for leaves out rows and items the viewer can't see" do
    statuses = Checklists.status_for(@checklist, [ person(:member), person(:kid) ], viewer: person(:parent))

    assert_equal [ person(:kid).id ], statuses.keys
    assert_nil statuses[person(:kid).id].item(@login_item.id)
    assert_equal :guardian, statuses[person(:kid).id].item(@safety_item.id).acts_for
  end

  # The person page

  test "a person's checklists show what to do, for themselves and a guardian" do
    with_feature do
      sign_in person(:kid).user
      get person_checklists_path(person(:kid))
      assert_response :success
      assert_match "Trip", response.body
      assert_match "Ask a leader", response.body

      sign_in person(:parent).user
      get person_checklists_path(person(:kid))
      assert_response :success
      assert_match "Safety", response.body
      assert_no_match ">Login<", response.body.gsub(/\s+/, "")
    end
  end

  test "a person sees no checklists for someone they can't see" do
    with_feature do
      sign_in person(:member2).user
      get person_checklists_path(person(:member))
      assert_response :success
      assert_match "No checklists to show", response.body
    end
  end

  test "the profile shows a Checklists tab to people who can see one of the person's checklists" do
    with_feature do
      sign_in person(:parent).user
      get person_path(person(:kid))
      assert_response :success
      assert_select "a.nav-link[href=?]", person_checklists_path(person(:kid)), text: "Checklists"

      sign_in person(:member2).user
      get person_path(person(:member))
      assert_select "a.nav-link", text: "Checklists", count: 0
    end
  end

  test "the Checklists tab is hidden when the feature is off or nothing covers the person" do
    sign_in person(:admin).user
    get person_path(person(:member))
    assert_select "a.nav-link", text: "Checklists", count: 0

    with_feature do
      get person_path(person(:outsider))
      assert_select "a.nav-link", text: "Checklists", count: 0
    end
  end

  # Running a checklist

  test "a manager makes a checklist and adds an item" do
    with_feature do
      sign_in person(:club_manager).user
      post checklists_path, params: { checklist: { title: "Season", team_id: @members.id, status: "draft", start_mode: "date", starts_on: "2026-09-01", read_level: "family" } }
      checklist = Checklist.find_by!(title: "Season")
      assert_redirected_to checklist_path(checklist)
      assert_includes checklist.organizers, person(:club_manager)

      post checklist_checklist_items_path(checklist), params: { checklist_item: { kind: "badge", label: "Safety", counts: "1", start_mode: "checklist", config: { badge_ids: [ @safety.id ], within_dates: "0" } } }
      assert_redirected_to checklist_path(checklist)
      assert_equal [ @safety.id ], checklist.checklist_items.first.config["badge_ids"]
    end
  end

  test "a member can't make or change a checklist" do
    with_feature do
      sign_in person(:member).user
      post checklists_path, params: { checklist: { title: "Mine", team_id: @members.id } }
      assert_not Checklist.exists?(title: "Mine")

      patch checklist_path(@checklist), params: { checklist: { title: "Hacked" } }
      assert_equal "Trip", @checklist.reload.title

      post checklist_checklist_items_path(@checklist), params: { checklist_item: { kind: "has_login", label: "Sneaky" } }
      assert_not ChecklistItem.exists?(label: "Sneaky")
    end
  end

  test "changing an active checklist's item shows the impact before saving" do
    with_feature do
      sign_in person(:admin).user
      patch checklist_checklist_item_path(@checklist, @safety_item), params: { checklist_item: { label: "Safety", config: { badge_ids: [ @viewer_badge.id ] } } }

      assert_response :unprocessable_entity
      assert_match "would go from Done to Not yet: Member World", response.body
      assert_equal [ @safety.id ], @safety_item.reload.config["badge_ids"]

      patch checklist_checklist_item_path(@checklist, @safety_item), params: { confirmed: "1", checklist_item: { label: "Safety", config: { badge_ids: [ @viewer_badge.id ] } } }
      assert_redirected_to checklist_path(@checklist)
      assert_equal [ @viewer_badge.id ], @safety_item.reload.config["badge_ids"]
    end
  end

  test "the live preview counts who a draft item passes, without saving" do
    with_feature do
      sign_in person(:admin).user
      assert_no_difference -> { ChecklistItem.count } do
        post preview_checklist_checklist_items_path(@checklist), params: { checklist_item: { kind: "badge", label: "Viewer", config: { badge_ids: [ @viewer_badge.id ] } } }
      end
      assert_response :success
      assert_match "Holds Report Viewer", response.body
      assert_match "Not yet", response.body
    end
  end

  test "an organizer adds and removes a population rule" do
    with_feature do
      sign_in person(:admin).user
      post checklist_checklist_rules_path(@checklist), params: { confirmed: "1", checklist_rule: { effect: "exclude", target_type: "person", person_id: person(:rookie).id } }
      assert_not_includes Checklists.people_covered_by(@checklist.reload), person(:rookie)

      rule = @checklist.checklist_rules.find_by(person: person(:rookie))
      delete checklist_checklist_rule_path(@checklist, rule), params: { confirmed: "1" }
      assert_includes Checklists.people_covered_by(@checklist.reload), person(:rookie)
    end
  end

  test "a non-admin badge can't grant access" do
    with_feature do
      sign_in person(:admin).user
      post checklist_checklist_grants_path(@checklist), params: { checklist_grant: { badge_id: @helper_badge.id, access: "full" } }

      assert_empty @checklist.checklist_grants
      assert_match "only admins give", flash[:alert]
    end
  end

  test "managers excuse with a reason; organizers and relatives can't" do
    with_settings(feature_checklists: "true", checklists_organizers: "Checklist Organizer > Club") do
      @checklist.checklist_organizers.create!(person: person(:organizer))
      sign_in person(:organizer).user
      post checklist_checklist_excuses_path(@checklist), params: { checklist_excuse: { item_id: @safety_item.id, person_id: person(:member2).id, reason: "Hurt" } }
      assert_empty ChecklistExcuse.all

      sign_in person(:club_manager).user
      post checklist_checklist_excuses_path(@checklist), params: { checklist_excuse: { item_id: @safety_item.id, person_id: person(:member2).id, reason: "Hurt" } }
      assert_redirected_to checklist_path(@checklist)
      assert_equal person(:club_manager), ChecklistExcuse.last.created_by

      Membership.create!(person: person(:parent), team: @club, manager: true)
      sign_in person(:parent).user
      post checklist_checklist_excuses_path(@checklist), params: { checklist_excuse: { item_id: @safety_item.id, person_id: person(:kid).id, reason: "Mine" } }
      assert_equal 1, ChecklistExcuse.count
    end
  end

  test "the excuse reason shows to managers only" do
    ChecklistExcuse.create!(item: @safety_item, person: person(:kid), reason: "Broken arm", created_by: person(:club_manager))
    refresh(@checklist)
    with_feature do
      sign_in person(:club_manager).user
      get checklist_path(@checklist)
      assert_match "Broken arm", response.body

      sign_in person(:parent).user
      get person_checklists_path(person(:kid))
      assert_match "Excused by ClubManager World", response.body
      assert_no_match "Broken arm", response.body
    end
  end

  test "a guardian confirms an attested item for their ward; a stranger can't" do
    item = add_item(@checklist, :attested, "Physical", { statement: "Physical on file", attested_by: "guardian" })
    with_feature do
      sign_in person(:member).user
      post checklist_checklist_attestations_path(@checklist, item_id: item.id, person_id: person(:kid).id)
      assert_empty ChecklistAttestation.all

      sign_in person(:parent).user
      post checklist_checklist_attestations_path(@checklist, item_id: item.id, person_id: person(:kid).id)
      attestation = ChecklistAttestation.last
      assert_equal person(:kid), attestation.person
      assert_equal person(:parent), attestation.attested_by
    end
  end

  test "an organizer copies a checklist and records a list" do
    with_feature do
      sign_in person(:admin).user
      get copy_checklist_path(@checklist)
      assert_response :success
      assert_match "Move dates by", response.body

      post copy_checklist_path(@checklist), params: { title: "Trip next", shift_months: 12, dates: { "checklist.starts_on" => "2027-09-01" } }
      copy = Checklist.find_by!(title: "Trip next")
      assert copy.draft?
      assert_equal Date.new(2027, 9, 1), copy.starts_on

      post checklist_checklist_lists_path(@checklist)
      list = @checklist.checklist_lists.last
      assert_redirected_to checklist_checklist_list_path(@checklist, list)
      get checklist_checklist_list_path(@checklist, list)
      assert_match "MemberTwo World", response.body
    end
  end

  test "a member can't record a list or see one" do
    list = ChecklistList.record!(@checklist, by: person(:admin))
    with_feature do
      sign_in person(:member).user
      post checklist_checklist_lists_path(@checklist)
      assert_equal 1, @checklist.checklist_lists.count

      get checklist_checklist_list_path(@checklist, list)
      assert_redirected_to root_path
    end
  end

  # Review fixes

  test "an organizer can't delete a confirmation for someone their checklist doesn't cover" do
    club_item = add_item(@checklist, :attested, "Physical", { statement: "Physical on file", attested_by: "person" })
    attestation = ChecklistAttestation.create!(person: person(:member), key: club_item.config["key"], statement: "Physical on file", attested_by: person(:member))
    crew = create_world_checklist("Crew", team: @crew)
    crew_item = add_item(crew, :attested, "Physical", { statement: "Physical on file", attested_by: "person" })
    Membership.create!(person: person(:crew_manager), team: @club)
    with_feature do
      sign_in person(:crew_manager).user
      delete checklist_checklist_attestation_path(crew, attestation, item_id: crew_item.id)

      assert_response :not_found
      assert ChecklistAttestation.exists?(attestation.id)
    end
  end

  test "an item can't name a checklist its maker can't see, nor preview one" do
    secret = create_world_checklist("Secret", team: @org)
    crew = create_world_checklist("Crew", team: @crew)
    with_feature do
      sign_in person(:crew_manager).user
      post checklist_checklist_items_path(crew), params: { checklist_item: { kind: "checklist", label: "Peek", config: { checklist_id: secret.id } } }
      assert_not crew.checklist_items.exists?(label: "Peek")
      assert_match "Choose a checklist", response.body

      post preview_checklist_checklist_items_path(crew), params: { checklist_item: { kind: "checklist", label: "Peek", config: { checklist_id: secret.id } } }
      assert_no_match "Secret", response.body
    end
  end

  test "the population preview ignores rules outside the checklist's team" do
    outside = Team.create!(name: "Elsewhere", team_type: team_types(:one), parent: @other_org, join_permission: :requires_approval)
    MembershipApplication.create!(person: person(:outsider), team: outside)
    with_feature do
      sign_in person(:club_manager).user
      post preview_checklist_path(@checklist), params: { checklist_rule: { effect: "include", target_type: "applicants", team_id: outside.id } }

      assert_response :success
      assert_no_match "Outsider", response.body
    end
  end

  test "a draft is hidden from the people it covers" do
    @checklist.update!(status: :draft)
    with_feature do
      sign_in person(:member).user
      get checklist_path(@checklist)
      assert_response :not_found

      get person_checklists_path(person(:member))
      assert_no_match "Trip", response.body
    end
  end

  test "an archived checklist can't be changed, but can be copied and restored" do
    @checklist.update!(status: :archived)
    with_feature do
      sign_in person(:admin).user
      post checklist_checklist_items_path(@checklist), params: { checklist_item: { kind: "has_login", label: "Late" } }
      assert_not ChecklistItem.exists?(label: "Late")
      patch checklist_path(@checklist), params: { checklist: { title: "Renamed" } }
      assert_equal "Trip", @checklist.reload.title

      get checklist_path(@checklist)
      assert_match "Archived: read-only", response.body
      assert_select "#setup", 0

      post restore_checklist_path(@checklist)
      assert @checklist.reload.active?
    end
  end

  test "sorting and filtering data carry only what the viewer may see" do
    hidden = add_item(@checklist, :badge, "Viewer", { badge_ids: [ @viewer_badge.id ] })
    @checklist.checklist_grants.create!(team: @crew, item_ids: [ @safety_item.id ], access: :full)
    refresh(@checklist)
    with_feature do
      sign_in person(:organizer).user
      get checklist_path(@checklist)

      assert_response :success
      assert_no_match ">Viewer<", response.body.gsub(/\s+/, "")
      assert_no_match hidden.id, response.body
      assert_no_match "3 to do", response.body
      assert_no_match "&quot;unmet&quot;:3", response.body
      assert_match "&quot;unmet&quot;:1", response.body, "MemberTwo misses only the one item the grant shows"
    end
  end

  test "the report offers tick filters on every column and number filters" do
    with_feature do
      sign_in person(:admin).user
      get checklist_path(@checklist)

      assert_select "input[data-checklist-report-target=tick][data-column='1']", 4
      assert_select "input[data-checklist-report-target=tick][data-column='2']", 4
      assert_select "input[data-checklist-report-target=bound][data-key=unmet]", 2
    end
  end

  test "adding or removing a rule on an active checklist shows the impact first" do
    with_feature do
      sign_in person(:admin).user
      post checklist_checklist_rules_path(@checklist), params: { checklist_rule: { effect: "exclude", target_type: "person", person_id: person(:member).id } }
      assert_response :unprocessable_entity
      assert_match "would go from Done to not covered: Member World", response.body
      assert_not @checklist.checklist_rules.exists?(person: person(:member))

      post checklist_checklist_rules_path(@checklist), params: { confirmed: "1", checklist_rule: { effect: "exclude", target_type: "person", person_id: person(:member).id } }
      rule = @checklist.checklist_rules.find_by!(person: person(:member))
      refresh(@checklist)

      delete checklist_checklist_rule_path(@checklist, rule)
      assert_response :unprocessable_entity
      assert ChecklistRule.exists?(rule.id)
      delete checklist_checklist_rule_path(@checklist, rule), params: { confirmed: "1" }
      assert_not ChecklistRule.exists?(rule.id)
    end
  end

  test "an item rule shows its impact too" do
    with_feature do
      sign_in person(:admin).user
      post checklist_checklist_rules_path(@checklist), params: { checklist_rule: { item_id: @safety_item.id, effect: "exclude", target_type: "person", person_id: person(:member2).id } }

      assert_response :unprocessable_entity
      assert_match "MemberTwo World", response.body
    end
  end

  test "removing an item shows its impact first" do
    with_feature do
      sign_in person(:admin).user
      delete checklist_checklist_item_path(@checklist, @safety_item)
      assert_response :unprocessable_entity
      assert_match "would go from Not yet to Done", response.body
      assert ChecklistItem.exists?(@safety_item.id)

      delete checklist_checklist_item_path(@checklist, @safety_item), params: { confirmed: "1" }
      assert_not ChecklistItem.exists?(@safety_item.id)
    end
  end

  test "the change banner names who changed it by role" do
    with_feature do
      sign_in person(:club_manager).user
      patch checklist_checklist_item_path(@checklist, @login_item), params: { confirmed: "1", checklist_item: { label: "Sign-in" } }
      get checklist_path(@checklist)

      assert_match "by a manager: item Sign-in edited", response.body
    end
  end

  test "a relative date setting shows as a choice and saves from the form" do
    Checklists.register_item_kind(:joined_since, ChecklistsTestKinds::JoinedSince)
    with_feature do
      sign_in person(:admin).user
      get new_checklist_checklist_item_path(@checklist, kind: "joined_since")
      assert_select "input[type=radio][name='checklist_item[config][since][mode]'][value=within]"
      assert_select "input[type=date][name='checklist_item[config][since][date]']"

      post checklist_checklist_items_path(@checklist), params: { confirmed: "1", checklist_item: { kind: "joined_since", label: "New",
        config: { since: { mode: "within", amount: "6", unit: "months", date: "", extra: "dropped" } } } }
      assert_equal({ "mode" => "within", "amount" => 6, "unit" => "months" }, @checklist.checklist_items.find_by!(label: "New").config["since"])
    end
  ensure
    Checklists.unregister_item_kind(:joined_since)
  end

  test "covered members see when and by whom a checklist changed, but not which item" do
    hidden = add_item(@checklist, :has_login, "Background check", {}, read_level: "guardians")
    PaperTrail.request(whodunnit: person(:admin).user.id) { hidden.update!(label: "Background check 2") }
    refresh(@checklist)
    with_feature do
      sign_in person(:member).user
      get checklist_path(@checklist)
      assert_match "by an admin", response.body
      assert_no_match "Background check 2", response.body

      sign_in person(:admin).user
      get checklist_path(@checklist)
      assert_match "item Background check 2 edited", response.body
    end
  end

  test "the copy page lists rules that will be left out" do
    gone = Person.create!(first_name: "Gone", last_name: "World")
    Membership.create!(person: gone, team: @members)
    add_rule(@checklist, :exclude, :person, person_id: gone.id)
    gone.destroy!
    with_feature do
      sign_in person(:admin).user
      get copy_checklist_path(@checklist)
      assert_match "1 rule naming a deleted person, team or badge will be left out", response.body

      post copy_checklist_path(@checklist), params: { title: "Next", shift_months: 12 }
      assert Checklist.exists?(title: "Next")
      assert_match "1 rule naming something deleted was left out", flash[:notice]
    end
  end

  test "confirming records the level it satisfied" do
    item = add_item(@checklist, :attested, "Permission", { statement: "Permission given", attested_by: "guardian" })
    with_feature do
      sign_in person(:parent).user
      post checklist_checklist_attestations_path(@checklist, item_id: item.id, person_id: person(:kid).id)
      assert_equal "guardian", ChecklistAttestation.last.attested_as
    end
  end

  test "the as-of picker computes live for organizers" do
    with_feature do
      sign_in person(:admin).user
      get checklist_path(@checklist, as_of: "2026-10-01")

      assert_response :success
      assert_match "nothing is saved", response.body
    end
  end
end
