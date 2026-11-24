require "test_helper"
require_relative "../support/checklists_world"

# The checklist screens in the standard shape: the record page's state line,
# filter bar and action row (Archive, Restore and Delete in More), the Edit
# page's tabs and Counting choice, and the list, snapshot and one-step pages.
class ChecklistScreensTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include ChecklistsWorld

  setup do
    host! "localhost"
    build_checklists_world
    @checklist = create_world_checklist("Trip")
    add_rule(@checklist, :include, :team, team_id: @members.id)
    @safety_item = add_item(@checklist, :badge, "Safety", { badge_ids: [ @safety.id ] })
    give_badge(:member, @safety)
    refresh(@checklist)
  end

  # Record page

  test "the footer shows Edit, Take Snapshot and More for a manager; a reader without manage sees none" do
    with_feature do
      sign_in person(:club_manager).user
      get checklist_path(@checklist)
      assert_response :success
      assert_select "[data-column-chooser-key-value=checklists-report][data-table-filter=off] .screen-filter-bar [data-column-chooser-target=slot]"
      assert_select "[data-column-chooser-label]", minimum: 1
      assert_select ".card-footer.screen-action-row" do
        assert_select "a.btn-warning[href=?]", edit_checklist_path(@checklist), text: "Edit"
        assert_select "form[action=?] button.btn-secondary", checklist_checklist_lists_path(@checklist), text: "Take Snapshot"
        assert_select "button.dropdown-toggle", text: "More"
        assert_select ".dropdown-menu .dropdown-item", text: "Recompute"
        assert_select ".dropdown-menu .dropdown-item", text: "Duplicate"
      end
      assert_select ".card-header a.btn, .card-header button.btn", 0, "no buttons left in the header"

      sign_in person(:member).user
      get checklist_path(@checklist)
      assert_response :success
      assert_select ".screen-action-row", 0
      assert_no_match "Take Snapshot", response.body
    end
  end

  test "the state line says whether the checklist counts, with a way to start a draft" do
    with_feature do
      sign_in person(:admin).user
      get checklist_path(@checklist)
      assert_select ".screen-state-line", text: "Counting now"

      @checklist.update!(status: :draft)
      get checklist_path(@checklist)
      assert_select ".screen-state-line", text: /\ANot counting yet: only the people who run it see it/
      assert_select ".screen-state-line a[href=?]", edit_checklist_path(@checklist, tab: "details"), text: "Start counting"

      @checklist.update!(status: :archived)
      get checklist_path(@checklist)
      assert_select ".screen-state-line", text: /\AArchived: read-only/
    end
  end

  test "each Counting choice sets the status, and the state line matches" do
    with_feature do
      sign_in person(:admin).user
      get edit_checklist_path(@checklist)
      assert_select "input[type=radio][name='checklist[status]']", 2
      assert_select "input[type=radio][name='checklist[status]'][value=draft] + label, label", text: /Not yet: only the people who run it see it, and nobody is notified/
      assert_select "label", text: /Yes, counting now: people see their progress/
      assert_select "select[name='checklist[status]']", 0

      { "draft" => /\ANot counting yet/, "active" => /\ACounting now\z/ }.each do |status, words|
        patch checklist_path(@checklist), params: { checklist: { status: status }, confirmed: "1" }
        assert_redirected_to checklist_path(@checklist)
        assert_equal status, @checklist.reload.status
        follow_redirect!
        assert_select ".screen-state-line", text: words
      end

      patch checklist_path(@checklist), params: { checklist: { status: "archived" }, confirmed: "1" }
      assert @checklist.reload.active?, "archiving is its own action, not a Counting choice"
    end
  end

  test "an organizer archives an active or a draft checklist and its results are kept" do
    with_feature do
      sign_in person(:club_manager).user
      draft = create_world_checklist("Draft trip", status: :draft)
      add_rule(draft, :include, :team, team_id: @members.id)
      refresh(draft)

      [ @checklist, draft ].each do |checklist|
        results = ChecklistResult.where(checklist: checklist).order(:id).pluck(:id, :person_id, :status)
        assert results.any?

        post archive_checklist_path(checklist)
        assert_redirected_to checklist_path(checklist)
        assert_equal "Checklist archived. It's read-only until restored.", flash[:notice]
        assert checklist.reload.archived?
        assert_equal results, ChecklistResult.where(checklist: checklist).order(:id).pluck(:id, :person_id, :status)
      end
    end
  end

  test "someone who doesn't run the checklist can't archive it, and an archived one can't be archived again" do
    with_feature do
      sign_in person(:member).user
      post archive_checklist_path(@checklist)
      assert_redirected_to root_path
      assert @checklist.reload.active?

      @checklist.update!(status: :archived)
      sign_in person(:club_manager).user
      post archive_checklist_path(@checklist)
      assert_redirected_to root_path
      assert @checklist.reload.archived?
    end
  end

  test "More offers Archive only when not archived and Restore only when archived, each with its confirm" do
    with_feature do
      sign_in person(:club_manager).user
      get checklist_path(@checklist)
      assert_select ".dropdown-menu form[action=?][data-turbo-confirm=?] button.dropdown-item", archive_checklist_path(@checklist),
        "Archive this checklist? It becomes read-only; results and snapshots are kept.", text: "Archive"
      assert_select "form[action=?]", restore_checklist_path(@checklist), 0

      @checklist.update!(status: :archived)
      get checklist_path(@checklist)
      assert_select ".dropdown-menu form[action=?][data-turbo-confirm=?] button.dropdown-item", restore_checklist_path(@checklist),
        "Restore this checklist? It starts counting again.", text: "Restore"
      assert_select "form[action=?]", archive_checklist_path(@checklist), 0
      assert_select "a[href=?]", edit_checklist_path(@checklist), 0
      assert_select ".dropdown-menu .dropdown-item", text: "Duplicate"

      post restore_checklist_path(@checklist)
      assert_redirected_to checklist_path(@checklist)
      assert @checklist.reload.active?
    end
  end

  test "Delete is the last More item, keeps its confirm and the same rule as before" do
    with_feature do
      sign_in person(:club_manager).user
      get checklist_path(@checklist)
      items = css_select(".dropdown-menu li:not(.d-md-none) .dropdown-item").map { |node| node.text.strip }
      assert_equal %w[Recompute Duplicate Archive Delete], items
      assert_select ".dropdown-menu form[action=?][data-turbo-confirm=?] button.dropdown-item.text-danger", checklist_path(@checklist),
        "Delete Trip and all its results?", text: "Delete"

      sign_in person(:member).user
      get checklist_path(@checklist)
      assert_select "form[action=?] input[name=_method][value=delete]", checklist_path(@checklist), 0
      delete checklist_path(@checklist)
      assert Checklist.exists?(@checklist.id), "a reader can't delete it"

      sign_in person(:club_manager).user
      delete checklist_path(@checklist)
      assert_redirected_to checklists_path
      assert_not Checklist.exists?(@checklist.id)
    end
  end

  test "the filter bar narrows the table by team and overall status, keeps the date, and offers Print" do
    add_rule(@checklist, :include, :team, team_id: @crew.id)
    refresh(@checklist)
    with_feature do
      sign_in person(:admin).user
      get checklist_path(@checklist)
      assert_select ".screen-filter-bar select[name=team_id] option", text: "Crew"
      assert_select ".screen-filter-bar select[name=team_id] option", text: "Members"
      assert_select ".screen-filter-bar input[type=date][name=as_of]"
      assert_select ".screen-table-actions button[data-action='checklist-report#print']", text: "Print"
      assert_select ".screen-filter-pills a", text: "Complete (1)"
      assert_match "Organizer World", response.body

      get checklist_path(@checklist, team_id: @members.id)
      assert_no_match "Organizer World", response.body
      assert_match "MemberTwo World", response.body

      get checklist_path(@checklist, status: "met")
      assert_select "tbody tr", 1
      assert_select "tbody tr a", text: "Member World"

      get checklist_path(@checklist)
      not_complete = css_select("tbody tr").size - 1
      assert_select ".screen-filter-pills a[href*='status=not_complete']", text: "Not complete (#{not_complete})"
      get checklist_path(@checklist, status: "not_complete")
      assert_select "tbody tr", not_complete
      assert_select "tbody tr a", text: "Member World", count: 0

      get checklist_path(@checklist, as_of: "2026-10-01", status: "met")
      assert_select ".screen-filter-pills a[href*='as_of=2026-10-01']", minimum: 1
    end
  end

  test "a reader's filter bar has no date and the table links to each person's checklists" do
    with_feature do
      sign_in person(:member).user
      get checklist_path(@checklist)
      assert_select "input[name=as_of]", 0
      assert_select "tbody a[href=?]", person_checklists_path(person(:member)), text: "Member World"
    end
  end

  # Edit page

  test "each setup tab saves its own part and comes back to it" do
    with_feature do
      sign_in person(:admin).user
      patch checklist_path(@checklist), params: { checklist: { title: "Trip 2026" } }
      assert_redirected_to checklist_path(@checklist)
      assert_equal "Trip 2026", @checklist.reload.title
      assert_equal 1, @checklist.checklist_items.count, "the details form leaves the items alone"

      post checklist_checklist_items_path(@checklist), params: { checklist_item: { kind: "has_login", label: "Login" }, confirmed: "1" }
      assert_redirected_to edit_checklist_path(@checklist, tab: "items")

      post checklist_checklist_rules_path(@checklist), params: { checklist_rule: { effect: "include", target_type: "team", team_id: @crew.id }, confirmed: "1" }
      assert_redirected_to edit_checklist_path(@checklist, tab: "covers")

      post checklist_checklist_grants_path(@checklist), params: { checklist_grant: { team_id: @crew.id, access: "status", overall: "1" } }
      assert_redirected_to edit_checklist_path(@checklist, tab: "access")

      post checklist_checklist_organizers_path(@checklist), params: { checklist_organizer: { person_id: person(:member).id } }
      assert_redirected_to edit_checklist_path(@checklist, tab: "access")
    end
  end

  test "the details tab has Cancel then Save, and asks Save anyway just above them when a change affects results" do
    with_feature do
      sign_in person(:admin).user
      get edit_checklist_path(@checklist)
      assert_equal [ "Cancel", "Save" ], css_select(".card-footer a.btn, .card-footer input[type=submit]").map { |node| node.text.presence || node["value"] }
      assert_select ".card-footer a.btn-secondary[href=?]", checklist_path(@checklist), text: "Cancel"

      patch checklist_path(@checklist), params: { checklist: { team_id: @crew.id } }
      assert_response :unprocessable_entity
      assert_equal @club.id, @checklist.reload.team_id
      assert_select ".nav-link", text: "Details"
      assert_equal [ "Save anyway", "Cancel", "Save" ], css_select(".card-footer a.btn, .card-footer input[type=submit]").map { |node| node.text.presence || node["value"] }

      patch checklist_path(@checklist), params: { checklist: { team_id: @crew.id }, confirmed: "1" }
      assert_redirected_to checklist_path(@checklist)
      assert_equal @crew.id, @checklist.reload.team_id
    end
  end

  test "a new checklist starts as Not yet and goes to its Items tab" do
    with_feature do
      sign_in person(:admin).user
      get new_checklist_path
      assert_select "input[type=radio][name='checklist[status]'][value=draft][checked]"
      assert_select ".card-footer a.btn-secondary[href=?]", checklists_path, text: "Cancel"

      post checklists_path, params: { checklist: { title: "Season", team_id: @members.id, status: "draft", start_mode: "date", starts_on: "2026-09-01", read_level: "family" } }
      checklist = Checklist.find_by!(title: "Season")
      assert checklist.draft?
      assert_redirected_to edit_checklist_path(checklist, tab: "items")
    end
  end

  test "item, rule and excuse forms use the standard buttons" do
    login = add_item(@checklist, :has_login, "Login")
    add_rule(@checklist, :include, :team, item: login, team_id: @members.id)
    with_feature do
      sign_in person(:admin).user
      get edit_checklist_checklist_item_path(@checklist, login)
      assert_equal [ "Cancel", "Save" ], css_select("form.simple_form a.btn, form.simple_form input[type=submit]").map { |node| node.text.presence || node["value"] }
      assert_select "a.btn-secondary[href=?]", edit_checklist_path(@checklist, tab: "items"), text: "Cancel"
      assert_select "input.btn-sm.btn-outline-secondary[value='Add rule']"
      assert_select "button.btn-sm.btn-outline-danger", text: "Remove"
      assert_select ".btn-link", 0

      get edit_checklist_path(@checklist, tab: "covers")
      assert_select "#covers button.btn-sm.btn-outline-danger", text: "Remove"

      get new_checklist_checklist_excuse_path(@checklist, item_id: @safety_item.id, person_id: person(:member2).id)
      assert_equal [ "Cancel", "Excuse" ], css_select("form.simple_form a.btn, form.simple_form input[type=submit]").map { |node| node.text.presence || node["value"] }
      assert_select "a.btn-secondary", text: "Cancel"
    end
  end

  # Other pages

  test "the list puts New Checklist, Search and Clear Search in its filter card's footer" do
    @checklist.update!(status: :draft)
    with_feature do
      sign_in person(:admin).user
      get checklists_path
      assert_equal [ "New Checklist", "Search", "Clear Search" ],
        css_select(".card-footer a.btn, .card-footer input[type=submit]").map { |node| node.text.presence || node["value"] }
      assert_select ".list-group-item .badge", text: "Not counting yet"
    end
  end

  test "the copy and change-check pages are one step: Cancel, then the effect" do
    with_feature do
      sign_in person(:admin).user
      get copy_checklist_path(@checklist)
      assert_select ".table-responsive table", minimum: 1
      assert_equal [ "Cancel", "Duplicate" ], css_select("form[method=post] a.btn, form[method=post] input[type=submit]").map { |node| node.text.presence || node["value"] }
      assert_select "a.btn-secondary[href=?]", checklist_path(@checklist), text: "Cancel"
      assert_select "input.btn-primary[value=Duplicate]"

      post checklist_checklist_rules_path(@checklist), params: { checklist_rule: { effect: "exclude", target_type: "person", person_id: person(:member).id } }
      assert_response :unprocessable_entity
      assert_equal [ "Cancel", "Make this change" ], css_select("form a.btn, form input[type=submit]").map { |node| node.text.presence || node["value"] }
      assert_select "input.btn-primary[value='Make this change']"
    end
  end

  test "a snapshot names the date it was taken and offers Print by its table" do
    with_feature do
      sign_in person(:admin).user
      post checklist_checklist_lists_path(@checklist)
      list = @checklist.checklist_lists.last
      get checklist_checklist_list_path(@checklist, list)
      assert_select ".card-body[data-controller~=column-chooser][data-column-chooser-key-value=checklists-list] table"
      assert_select ".card-header h1", text: "Trip"
      assert_select ".card-header .text-muted", text: /\ATaken #{Regexp.escape(I18n.l(list.recorded_at, format: :long))} by Admin World/
      assert_select ".screen-table-actions button", text: "Print"
      assert_select ".table-responsive table"
    end
  end
end
