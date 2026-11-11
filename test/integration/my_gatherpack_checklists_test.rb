require "test_helper"
require_relative "../support/checklists_world"
require_relative "../support/checklists_test_kinds"

# Checklists on the home page and menu: to-do rows, Your Checklists and Manage.
class MyGatherpackChecklistsTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include ChecklistsWorld

  # A counting item: confirmed of owed, like a commitment's.
  class Shifts < Checklists::ItemKind
    def evaluate(person_ids)
      person_ids.index_with { Checklists::Result.not_met("1 of 3 shifts", measures: { "confirmed" => 1, "owed" => 3 }) }
    end
  end

  # A counting item measured in hours, like attendance.
  class Hours < Checklists::ItemKind
    def self.measures
      [ Checklists::ItemKind::Measure.new(key: :confirmed, label: "Hours toward the minimum", type: :hours),
        Checklists::ItemKind::Measure.new(key: :owed, label: "Hours needed", type: :hours) ]
    end

    def evaluate(person_ids)
      person_ids.index_with { Checklists::Result.not_met("Below", measures: { "confirmed" => 2.5, "owed" => 4.0 }) }
    end
  end

  # A fix anyone can use: a plain link.
  class Plain < Checklists::ItemKind
    def evaluate(person_ids)
      person_ids.index_with { Checklists::Result.not_met("Not yet", fix: { "label" => "Fill out", "path" => "/forms" }) }
    end
  end

  setup do
    host! "localhost"
    @original_sections = MyGatherpack.sections.dup
    @original_table = MyGatherpack::Menu.table.dup
    @original_checks = MyGatherpack::Menu.manager_checks.dup
    Checklists.register_item_kind(:fix_link, ChecklistsTestKinds::FixLink)
    Checklists.register_item_kind(:shifts, Shifts)
    Checklists.register_item_kind(:plain, Plain)
    Checklists.register_item_kind(:hours, Hours)
    build_checklists_world
    @checklist = create_world_checklist("Trip")
    add_rule(@checklist, :include, :person, person_id: person(:member).id)
    add_rule(@checklist, :include, :person, person_id: person(:kid).id)
    # The admin is covered through a team, like anyone else.
    Membership.create!(person: person(:admin), team: @members)
    Membership.create!(person: person(:parent), team: @members)
  end

  teardown do
    Checklists.unregister_item_kind(:fix_link)
    Checklists.unregister_item_kind(:shifts)
    Checklists.unregister_item_kind(:plain)
    Checklists.unregister_item_kind(:hours)
    MyGatherpack.sections.replace(@original_sections)
    MyGatherpack::Menu.table = @original_table
    MyGatherpack::Menu.manager_checks.replace(@original_checks)
  end

  test "the sections are registered" do
    assert_equal :todo, MyGatherpack.sections[:checklists_todo].column
    assert MyGatherpack.sections[:checklists_todo].items
    assert_equal :side, MyGatherpack.sections[:checklists_season].column
  end

  test "the sections show with the feature flag and hide without it, and with nothing to show" do
    badge_item = add_item(@checklist, :plain, "Form")
    refresh(@checklist)

    with_settings(feature_my_gatherpack: "true", feature_checklists: "false") do
      sign_in person(:admin).user
      get root_path
      assert_select "[data-home-column=todo]", false
      assert_select "[data-home-section=checklists-season]", false
    end

    with_settings(feature_my_gatherpack: "true", feature_checklists: "true") do
      sign_in person(:member).user
      get root_path
      assert_select "h1", text: "Hi Member. You have 1 thing to do."
      assert_select "[data-home-section=checklists-season] h2", text: "Your Checklists"

      badge_item.destroy
      refresh(@checklist)
      get root_path
      assert_select "h1", text: "Hi Member. You're all caught up."
      assert_select "[data-home-column=todo]", false
      assert_select "[data-home-section=checklists-season]", false
    end
  end

  test "to-do rows sort past due first, then nearest, then undated" do
    add_item(@checklist, :plain, "Undated", {})
    add_item(@checklist, :plain, "Next month", {}, due_on: 1.month.from_now.to_date)
    add_item(@checklist, :plain, "Tomorrow", {}, due_on: 1.day.from_now.to_date)
    add_item(@checklist, :plain, "Last week", {}, due_on: 1.week.ago.to_date)
    refresh(@checklist)

    with_feature_on do
      sign_in person(:admin).user
      add_rule(@checklist, :include, :person, person_id: person(:admin).id)
      refresh(@checklist)
      get root_path

      assert_select "h1", text: "Hi Admin. You have 4 things to do."
      assert_equal [ "Last week", "Tomorrow", "Next month", "Undated" ], css_select("[data-home-column=todo] .mg-row-title").map { |t| t.text.strip.sub(/\s+for .*/, "") }
      assert_select "[data-home-column=todo] .mg-row-detail-late", text: /Last week|Trip/
    end
  end

  test "a row names the ward only on a ward's row, and guardian wording only there" do
    confirm = add_item(@checklist, :attested, "Permission", { statement: "Permission given", attested_by: "guardian" })
    add_rule(@checklist, :include, :person, person_id: person(:parent).id)
    refresh(@checklist)

    with_feature_on do
      sign_in person(:parent).user
      get root_path

      rows = css_select("[data-home-column=todo] .mg-row")
      assert_equal 2, rows.size
      ward_row = rows.find { |row| row.css(".mg-row-ward").any? }
      own_row = rows.find { |row| row.css(".mg-row-ward").empty? }
      assert_equal "for Kid", ward_row.css(".mg-row-ward").text.strip
      assert_equal [ "Confirm for Kid" ], ward_row.css("a.btn").map { |link| link.text.strip }
      assert_no_match(/Kid|for /, own_row.text)
      assert confirm
    end
  end

  test "a row matches the checklists page for the same person" do
    add_item(@checklist, :fix_link, "Badge", { badge_id: @safety.id })
    add_item(@checklist, :attested, "Course", { statement: "Course done", attested_by: "person" })
    refresh(@checklist)

    [ :member, :admin ].each do |viewer|
      add_rule(@checklist, :include, :person, person_id: person(viewer).id) unless @checklist.checklist_rules.exists?(person_id: person(viewer).id)
      refresh(@checklist)
      with_feature_on do
        sign_in person(viewer).user
        get person_checklists_path(person(viewer))
        page = css_select("li.list-group-item").to_h do |li|
          [ li.at_css("strong").text, li.css("a.btn, button.btn").map { |control| [ control.text.strip, control["href"] ] } ]
        end

        get root_path
        rows = css_select("[data-home-column=todo] .mg-row")
        assert_operator rows.size, :>=, 1
        rows.each do |row|
          title = row.at_css(".mg-row-title").text.strip
          link = row.at_css("a.btn")
          control = page.fetch(title).first
          assert_equal control.first, link.text.strip, "#{viewer} #{title}"
          assert_equal control.last, link["href"] if control.last
        end
      end
    end
  end

  test "a link the viewer's policy doesn't allow isn't a row" do
    add_item(@checklist, :fix_link, "Badge", { badge_id: @safety.id })
    refresh(@checklist)

    with_feature_on do
      sign_in person(:member).user
      get root_path
      assert_select "h1", text: "Hi Member. You're all caught up."

      add_rule(@checklist, :include, :person, person_id: person(:admin).id)
      refresh(@checklist)
      sign_in person(:admin).user
      get root_path
      assert_select "[data-home-column=todo] a.btn[href=?]", badge_path(@safety), text: "Edit the badge"
    end
  end

  test "an item the checklist hides from a guardian isn't a row for them" do
    add_item(@checklist, :plain, "Private", {}, read_level: "self_and_leaders")
    add_rule(@checklist, :include, :person, person_id: person(:parent).id)
    refresh(@checklist)

    with_feature_on do
      sign_in person(:parent).user
      get person_checklists_path(person(:kid))
      assert_no_match "Private", response.body
      get root_path
      assert_no_match(/for Kid/, response.body)
    end
  end

  test "Your Checklists shows a progress bar, and a count item reads confirmed of owed" do
    add_item(@checklist, :shifts, "Shifts")
    add_item(@checklist, :has_login, "Login")
    refresh(@checklist)

    with_feature_on do
      sign_in person(:member).user
      get root_path

      assert_select "[data-home-section=checklists-season] .mg-season-item a", text: "Shifts"
      assert_select "[data-home-section=checklists-season] .mg-season-item span", text: "1 of 3"
      assert_select "[data-home-section=checklists-season] .progress-bar.bg-danger[style*='width: 33%']", true, "a shortfall shows in the not-met pill color"
    end
  end

  test "Your Checklists shows a finished yes/no item as a status pill, not a bar or a percentage" do
    add_item(@checklist, :shifts, "Shifts")
    add_item(@checklist, :has_login, "Login")
    refresh(@checklist)

    with_feature_on do
      sign_in person(:member).user
      get root_path

      assert_equal %w[Shifts Login], css_select("[data-home-section=checklists-season] .mg-season-item a").map { |link| link.text.strip }
      login = css_select("[data-home-section=checklists-season] .mg-season-item").find { |item| item.text.include?("Login") }
      assert_equal "Complete", login.css(".badge").text.strip
      assert_empty login.css(".progress"), "a yes/no item has nothing to measure"
      assert_select "[data-home-section=checklists-season] .mg-row-detail", false, "the pill says it all: no status sentence under an item"
      assert_no_match "100%", css_select("[data-home-section=checklists-season]").text
    end
  end

  test "an item measured in hours reads confirmed of owed h" do
    add_item(@checklist, :hours, "Attendance")
    refresh(@checklist)

    with_feature_on do
      sign_in person(:member).user
      get root_path

      assert_select "[data-home-section=checklists-season] .mg-season-item span", text: "2.5 of 4 h"
      assert_select "[data-home-section=checklists-season] .progress-bar[style*='width: 62%']"
    end
  end

  test "a one-item checklist another checklist already shows as a line has no card of its own" do
    concessions = create_world_checklist("Concessions")
    add_rule(concessions, :include, :person, person_id: person(:member).id)
    add_item(concessions, :shifts, "Concessions")
    workshops = create_world_checklist("Workshops")
    add_rule(workshops, :include, :person, person_id: person(:member).id)
    add_item(workshops, :shifts, "Build")
    add_item(workshops, :has_login, "Login")
    add_item(@checklist, :checklist, "Concessions", { checklist_id: concessions.id })
    add_item(@checklist, :checklist, "Workshops", { checklist_id: workshops.id })
    [ concessions, workshops, @checklist ].each { |checklist| refresh(checklist) }

    with_feature_on do
      sign_in person(:member).user
      get root_path

      titles = css_select("[data-home-section=checklists-season] .mg-row-title a").map { |link| link.text.strip }
      assert_includes titles, "Trip"
      assert_not_includes titles, "Concessions", "the Trip line says it all"
      assert_includes titles, "Workshops", "two items can't fit on one line"
      assert_select "[data-home-section=checklists-season] .mg-season-item a[href=?]", checklist_path(concessions), text: "Concessions"
    end
  end

  test "a checklist with everything finished stays in Your Checklists" do
    add_item(@checklist, :has_login, "Login")
    refresh(@checklist)

    with_feature_on do
      sign_in person(:member).user
      get root_path

      assert_select "[data-home-column=todo]", false
      assert_select "[data-home-section=checklists-season] .mg-season-item a", text: "Login"
    end
  end

  test "an ended checklist is no to-do and not in Your Checklists" do
    ended = create_world_checklist("Last season", ends_on: 1.week.ago.to_date)
    add_rule(ended, :include, :person, person_id: person(:member).id)
    add_item(ended, :plain, "Old form")
    refresh(ended)

    with_feature_on do
      sign_in person(:member).user
      get root_path

      assert_select "h1", text: "Hi Member. You're all caught up."
      assert_select "[data-home-section=checklists-season]", false
    end
  end

  test "a ward with no first name still gets a label, a ward link and guardian wording" do
    person(:kid).update_columns(first_name: nil)
    add_item(@checklist, :attested, "Permission", { statement: "Permission given", attested_by: "guardian" })
    add_rule(@checklist, :include, :person, person_id: person(:parent).id)
    refresh(@checklist)

    with_feature_on do
      sign_in person(:parent).user
      get root_path

      label = "for #{person(:kid).identifier_name}"
      assert_select "[data-home-column=todo] .mg-row-ward", text: label
      assert_select "[data-home-column=todo] a.btn", text: "Confirm for #{person(:kid).identifier_name}"
      assert_select "[data-home-section=checklists-season] a[href=?]", person_checklists_path(person(:kid))
    end
  end

  test "a pointer to what only a leader can finish is a row for an organizer, not for the member" do
    prereq = create_world_checklist("Prereq")
    add_rule(prereq, :include, :person, person_id: person(:member).id)
    add_item(prereq, :badge, "Safety", { badge_ids: [ @safety.id ] })
    add_item(@checklist, :checklist, "Prereq done", { checklist_id: prereq.id })
    refresh(prereq)
    refresh(@checklist)

    with_feature_on do
      sign_in person(:member).user
      get root_path
      assert_select "h1", text: "Hi Member. You're all caught up."

      sign_in person(:admin).user
      add_rule(prereq, :include, :person, person_id: person(:admin).id)
      add_rule(@checklist, :include, :person, person_id: person(:admin).id) unless @checklist.checklist_rules.exists?(person_id: person(:admin).id)
      refresh(prereq)
      refresh(@checklist)
      get root_path
      assert_select "[data-home-column=todo] .mg-row"
    end
  end

  test "an item without a count shows no bar" do
    add_item(@checklist, :has_login, "Login")
    add_item(@checklist, :plain, "Shown only", {}, counts: false)
    refresh(@checklist)

    with_feature_on do
      sign_in person(:member).user
      get root_path

      row = css_select("[data-home-section=checklists-season] .mg-season-item").find { |item| item.text.include?("Shown only") }
      assert row, "Shown only is listed"
      assert_empty row.css(".progress-bar")
    end
  end

  test "an organizer gets Manage with Checklists in it; a plain member doesn't" do
    with_settings(feature_my_gatherpack: "true", feature_checklists: "true", checklists_organizers: "Checklist Organizer > Club") do
      sign_in person(:organizer).user
      menu = MyGatherpack::Menu.new(person(:organizer).user)
      assert menu.manages_anything?
      assert_includes menu.manage.map(&:path), :checklists_path

      assert_not MyGatherpack::Menu.new(person(:member).user).manages_anything?
    end
  end

  test "a team manager sees Checklists in Manage, not More" do
    with_feature_on do
      menu = MyGatherpack::Menu.new(person(:club_manager).user)
      assert_includes menu.manage.map(&:path), :checklists_path
      assert_not_includes menu.more.map(&:path), :checklists_path
    end
  end

  private

  def with_feature_on(&block)
    with_settings(feature_my_gatherpack: "true", feature_checklists: "true", &block)
  end
end
