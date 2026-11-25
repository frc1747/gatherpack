require "test_helper"
require_relative "../support/checklists_world"
require_relative "../support/checklists_test_kinds"

# Checklists on the home page and menu: to-do rows, My Season and Manage.
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

  # Met, with what the person did measured in hours, against rule groups
  # by date, like attendance: credited hours are the person's own, confirmed
  # stops at the minimum.
  class Attended < Checklists::ItemKind
    def self.measures
      [ Checklists::ItemKind::Measure.new(key: :credited, label: "Hours at meetings", type: :hours),
        Checklists::ItemKind::Measure.new(key: :confirmed, label: "Hours toward the minimum", type: :hours),
        Checklists::ItemKind::Measure.new(key: :owed, label: "Hours needed", type: :hours) ]
    end

    def self.rules(item) = Checklists::Kinds::Attendance.rules(item)

    def evaluate(person_ids)
      person_ids.index_with do
        Checklists::Result.met("93% of 8.7 h", detail: "✓ Fall: 8.1 h of 8.7 h (needs 8.1 h)", measures: { "credited" => 44, "confirmed" => 8.1, "owed" => 8.1 })
      end
    end
  end

  # Met, counting events past what's owed.
  class Outreach < Checklists::ItemKind
    def evaluate(person_ids)
      person_ids.index_with { Checklists::Result.met("5 of 3 events", measures: { "confirmed" => 5, "owed" => 3, "remaining" => 0 }) }
    end
  end

  # Not met, with what's left counted for a group, like a pooled commitment.
  class Pooled < Checklists::ItemKind
    def evaluate(person_ids)
      person_ids.index_with { Checklists::Result.not_met("2 of 3 shifts", measures: { "confirmed" => 2, "owed" => 3, "remaining" => 1 }) }
    end
  end

  # Not met, nothing measured and no fix: in progress, not a to-do.
  class Waiting < Checklists::ItemKind
    def evaluate(person_ids)
      person_ids.index_with { Checklists::Result.not_met("Not yet", detail: "Waiting on the team's paperwork") }
    end
  end

  # Not met, counted, with a sign-up as its fix: a to-do row.
  class OpenShifts < Checklists::ItemKind
    def evaluate(person_ids)
      person_ids.index_with do
        Checklists::Result.not_met("1 of 3 shifts", measures: { "confirmed" => 1, "owed" => 3, "remaining" => 2 },
          fix: { "label" => "Next: Sat shift", "path" => "/signups", "by" => "person" })
      end
    end
  end

  # Pending: some of what's owed is signed up for, not yet done.
  class SignedUp < Checklists::ItemKind
    def evaluate(person_ids)
      person_ids.index_with { Checklists::Result.pending("1 of 3 shifts", measures: { "confirmed" => 1, "planned" => config["planned"], "owed" => 3, "remaining" => 2 }) }
    end
  end

  # Not met: nothing done yet, some signed up for. remaining is what the
  # item's counting leaves, given in config.
  class Behind < Checklists::ItemKind
    def evaluate(person_ids)
      person_ids.index_with { Checklists::Result.not_met("0 of 3 shifts", measures: { "confirmed" => 0, "planned" => 1, "owed" => 3, "remaining" => config["remaining"] }) }
    end
  end

  # Met with its own word.
  class Signed < Checklists::ItemKind
    def evaluate(person_ids)
      person_ids.index_with { Checklists::Result.met("Signed", label: "Signed") }
    end
  end

  # Doesn't apply to anyone, with its label.
  class Rookie < Checklists::ItemKind
    def evaluate(person_ids)
      person_ids.index_with { Checklists::Result.exempt("Rookie") }
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
    Checklists.register_item_kind(:open_shifts, OpenShifts)
    Checklists.register_item_kind(:signed_up, SignedUp)
    Checklists.register_item_kind(:behind, Behind)
    Checklists.register_item_kind(:attended, Attended)
    Checklists.register_item_kind(:outreach, Outreach)
    Checklists.register_item_kind(:pooled, Pooled)
    Checklists.register_item_kind(:waiting, Waiting)
    Checklists.register_item_kind(:signed, Signed)
    Checklists.register_item_kind(:rookie, Rookie)
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
    Checklists.unregister_item_kind(:open_shifts)
    Checklists.unregister_item_kind(:signed_up)
    Checklists.unregister_item_kind(:behind)
    Checklists.unregister_item_kind(:attended)
    Checklists.unregister_item_kind(:outreach)
    Checklists.unregister_item_kind(:pooled)
    Checklists.unregister_item_kind(:waiting)
    Checklists.unregister_item_kind(:signed)
    Checklists.unregister_item_kind(:rookie)
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
    signed_item = add_item(@checklist, :signed, "Consent")
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
      assert_select "[data-home-section=checklists-season] h2", text: "My Season"

      [ badge_item, signed_item ].each(&:destroy)
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

  test "a met item with a measure says what the person did, not the threshold" do
    add_item(@checklist, :attended, "Attendance").update_columns(config: { "rules" => [
      { "name" => "Fall", "starts" => { "mode" => "date", "date" => 1.month.ago.to_date.iso8601 }, "ends_on" => 1.month.from_now.to_date.iso8601, "share" => 50 },
      { "name" => "Spring", "starts" => { "mode" => "date", "date" => 2.months.from_now.to_date.iso8601 }, "share" => 50 }
    ] })
    add_item(@checklist, :outreach, "Outreach").update_columns(config: { "unit" => "events" })
    refresh(@checklist)

    with_feature_on do
      sign_in person(:member).user
      get root_path

      assert_equal [ "Attendance ✓ 44 h this fall", "Outreach ✓ 5 events" ], season_lines("done")
      assert_no_match(/8\.1|of 3/, season_lines("done").join(" "), "never the threshold")
    end
  end

  test "an item's rule group with no name of its own is this season" do
    add_item(@checklist, :attended, "Attendance").update_columns(config: { "rules" => [ { "share" => 50 } ] })
    refresh(@checklist)

    with_feature_on do
      sign_in person(:member).user
      get root_path
      assert_equal [ "Attendance ✓ 44 h this season" ], season_lines("done")
    end
  end

  test "a met item without a measure says its status word" do
    add_item(@checklist, :signed, "Consent")
    add_item(@checklist, :has_login, "Login")
    refresh(@checklist)

    with_feature_on do
      sign_in person(:member).user
      get root_path
      assert_equal [ "Consent ✓ Signed", "Login ✓ Complete" ], season_lines("done")
    end
  end

  test "an unfinished item with a measure says the gap, and the due date when it has one" do
    add_item(@checklist, :hours, "Attendance", {}, due_on: Date.new(Date.current.year, 12, 31))
    add_item(@checklist, :shifts, "Concessions").update_columns(config: { "unit" => "shifts" })
    refresh(@checklist)

    with_feature_on do
      sign_in person(:member).user
      get root_path
      assert_equal [ "Attendance 1.5 more hours by Dec 31", "Concessions 2 more shifts" ], season_lines("in-progress")
      assert_select "[data-season-group=in-progress] .mg-season-count", text: "2"
      assert_select "[data-season-group=in-progress] summary .mg-season-unfinished .mg-season-alert[aria-label='Not done yet']", 2
    end
  end

  test "a pending count takes off what's signed up, and says so when that covers it" do
    add_item(@checklist, :signed_up, "Concessions").update_columns(config: { "unit" => "shifts", "planned" => 2 })
    add_item(@checklist, :signed_up, "Pit crew").update_columns(config: { "unit" => "shifts", "planned" => 1 })
    refresh(@checklist)

    with_feature_on do
      sign_in person(:member).user
      get root_path
      assert_equal [ "Concessions 2 shifts signed up", "Pit crew 1 more shift" ], season_lines("in-progress")
    end
  end

  test "a count not met takes off what's signed up, unless sign-ups already count" do
    add_item(@checklist, :behind, "Concessions").update_columns(config: { "unit" => "shifts", "remaining" => 3 })
    add_item(@checklist, :behind, "Pit crew").update_columns(config: { "unit" => "shifts", "remaining" => 2, "counts_when" => "planned" })
    refresh(@checklist)

    with_feature_on do
      sign_in person(:member).user
      get root_path
      assert_equal [ "Concessions 2 more shifts", "Pit crew 2 more shifts" ], season_lines("in-progress")
    end
  end

  test "an item past its due date says when it was due" do
    due = 1.week.ago.to_date
    add_item(@checklist, :hours, "Attendance", {}, due_on: due)
    refresh(@checklist)

    with_feature_on do
      sign_in person(:member).user
      get root_path
      assert_equal [ "Attendance 1.5 more hours, was due #{due.strftime("%b %-d")}" ], season_lines("in-progress")
    end
  end

  test "an unfinished item without a measure says its status word" do
    add_item(@checklist, :waiting, "Paperwork")
    refresh(@checklist)

    with_feature_on do
      sign_in person(:member).user
      get root_path
      assert_equal [ "Paperwork Not Started" ], season_lines("in-progress")
    end
  end

  test "an exempt item is in Done with its label" do
    add_item(@checklist, :rookie, "Outreach")
    add_item(@checklist, :waiting, "Paperwork")
    refresh(@checklist)

    with_feature_on do
      sign_in person(:member).user
      get root_path
      assert_equal [ "Outreach · Rookie" ], season_lines("done")
      assert_select "[data-season-group=done] .mg-season-alert", 0
      assert_equal [ "Paperwork Not Started" ], season_lines("in-progress")
    end
  end

  test "a count owed together gives the gap for the family" do
    add_item(@checklist, :pooled, "Concessions").update_columns(config: { "unit" => "shifts", "group_relationship_type_id" => SecureRandom.uuid })
    refresh(@checklist)

    with_feature_on do
      sign_in person(:member).user
      get root_path
      assert_equal [ "Concessions 1 more shift for your family" ], season_lines("in-progress")
    end
  end

  test "Home has no x of y and no bar, while the checklists page keeps the count" do
    add_item(@checklist, :open_shifts, "Concessions").update_columns(config: { "unit" => "shifts" })
    add_item(@checklist, :shifts, "Shifts")
    add_item(@checklist, :hours, "Attendance")
    add_item(@checklist, :has_login, "Login")
    refresh(@checklist)

    with_feature_on do
      sign_in person(:member).user
      get root_path
      lines = css_select("[data-home-section=checklists-season] summary, [data-home-column=todo] .mg-row").map(&:text)
      assert_equal 3, css_select("[data-home-section=checklists-season] summary").size
      assert_select "[data-home-column=todo] .mg-row-detail", text: /2 more shifts/
      assert_no_match(/\d+(\.\d+)? of \d+/, lines.join(" "), "the formula is only in a line's detail, shown when it's tapped")
      assert_select ".progress, .progress-bar, [role=progressbar]", false

      get person_checklists_path(person(:member))
      assert_match "1 of 3 shifts", response.body
    end
  end

  test "tapping a line shows the detail the checklists page shows" do
    add_item(@checklist, :attended, "Attendance").update_columns(config: { "rules" => [ { "name" => "Fall", "share" => 50 } ] })
    add_item(@checklist, :waiting, "Paperwork")
    refresh(@checklist)

    with_feature_on do
      sign_in person(:member).user
      get root_path
      line = css_select("[data-home-section=checklists-season] details.mg-season-item").find { |item| item.at_css("summary").text.include?("Attendance") }
      assert_match "✓ Fall: 8.1 h of 8.7 h (needs 8.1 h)", line.at_css(".mg-season-detail").text
      assert_equal checklist_path(@checklist), line.at_css(".mg-season-detail a")["href"]
      paperwork = css_select("[data-home-section=checklists-season] details.mg-season-item").find { |item| item.text.include?("Paperwork") }
      assert_match "Waiting on the team's paperwork", paperwork.at_css(".mg-season-detail").text

      get person_checklists_path(person(:member))
      assert_match "✓ Fall: 8.1 h of 8.7 h (needs 8.1 h)", response.body
    end
  end

  test "Done is one line of titles that a button expands" do
    add_item(@checklist, :signed, "Consent")
    add_item(@checklist, :has_login, "Login")
    add_item(@checklist, :waiting, "Paperwork")
    refresh(@checklist)

    with_feature_on do
      sign_in person(:member).user
      get root_path

      button = css_select("[data-season-group=done] button.mg-season-done").first
      assert button, "Done is a button"
      assert_equal "false", button["aria-expanded"]
      assert_equal "Consent, Login", button.at_css(".mg-season-done-titles").text.strip
      assert_select "[data-season-group=done] ##{button["aria-controls"]}.collapse details", 2
      assert_select "[data-season-group=in-progress] details", 1
      assert_select ".mg-season-all-set", false, "something is still in progress"
    end
  end

  test "with nothing to do or in progress, My Season says you're all set" do
    add_item(@checklist, :signed, "Consent")
    refresh(@checklist)

    with_feature_on do
      sign_in person(:member).user
      get root_path
      assert_select "[data-home-section=checklists-season] .mg-season-all-set", text: "You're all set for now"

      add_item(@checklist, :plain, "Form")
      refresh(@checklist)
      get root_path
      assert_select ".mg-season-all-set", false, "a to-do is something to do"
    end
  end

  test "an item that is a to-do row isn't in My Season too" do
    add_item(@checklist, :plain, "Form")
    add_item(@checklist, :waiting, "Paperwork")
    add_item(@checklist, :signed, "Consent")
    refresh(@checklist)

    with_feature_on do
      sign_in person(:member).user
      get root_path

      assert_select "[data-home-column=todo] .mg-row-title", text: "Form"
      season = css_select("[data-home-section=checklists-season] .mg-season-title").map { |title| title.text.strip }
      assert_equal %w[Paperwork Consent], season
    end
  end

  test "a form a checklist item lists is claimed, so the forms section can leave its row out" do
    form_id = SecureRandom.uuid
    add_item(@checklist, :plain, "Permission form").update_columns(config: { "form_ids" => [ form_id ] })
    refresh(@checklist)

    with_feature_on do
      sign_in person(:member).user
      get root_path
      view = controller.view_context
      assert MyGatherpack::Claims.claimed?(view, :form, person(:member), form_id)
      assert_not MyGatherpack::Claims.claimed?(view, :form, person(:member), SecureRandom.uuid)
      assert_not MyGatherpack::Claims.claimed?(view, :form, person(:admin), form_id), "a checklist that doesn't cover them claims nothing"
    end
  end

  test "a line for a checklist that has ended still reads as finished for someone it covered" do
    prereq = create_world_checklist("Prereq")
    add_rule(prereq, :include, :person, person_id: person(:member).id)
    add_item(prereq, :signed, "Letter")
    add_item(@checklist, :checklist, "Prereq done", { checklist_id: prereq.id })
    refresh(prereq)
    refresh(@checklist)
    prereq.update_columns(ends_on: 1.day.ago.to_date)

    with_feature_on do
      sign_in person(:member).user
      get root_path
      line = season_lines("done").find { |text| text.start_with?("Prereq done") }
      assert_equal "Prereq done ✓ Complete", line
      assert_select "a[href=?]", checklist_path(prereq), false, "an ended checklist isn't one to open from Home"
    end
  end

  test "a ward's line for a checklist that covers the guardian but not the ward names nothing" do
    other = create_world_checklist("Varsity Only")
    add_rule(other, :include, :person, person_id: person(:parent).id)
    add_item(other, :signed, "Letter")
    add_item(@checklist, :checklist, "Varsity", { checklist_id: other.id })
    refresh(other)
    refresh(@checklist)

    with_feature_on do
      sign_in person(:parent).user
      get root_path
      line = css_select("[data-season-person=\"#{person(:kid).id}\"] details.mg-season-item").find do |item|
        item.at_css(".mg-season-title")&.text == "Varsity"
      end
      assert line, "the ward's line is there"
      assert_match "Not required for you", line.at_css("summary").text
      assert_no_match "Varsity Only", line.to_html
      assert_empty line.css("a[href='#{checklist_path(other)}']")
    end
  end

  test "Home never names or links a checklist that doesn't cover the person" do
    other = create_world_checklist("Varsity Only")
    add_rule(other, :include, :person, person_id: person(:admin).id)
    add_item(other, :signed, "Letter")
    add_item(@checklist, :checklist, "Varsity", { checklist_id: other.id })
    add_item(@checklist, :signed, "Consent")
    refresh(other)
    refresh(@checklist)

    with_feature_on do
      sign_in person(:member).user
      get root_path
      assert_no_match "Varsity Only", response.body
      assert_select "a[href=?]", checklist_path(other), false
      assert_includes season_lines("done"), "Varsity · Not required for you"
    end
  end

  test "a one-item checklist another checklist already shows as a line has no lines of its own" do
    concessions = create_world_checklist("Concessions")
    add_rule(concessions, :include, :person, person_id: person(:member).id)
    add_item(concessions, :shifts, "Concession shifts")
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

      titles = css_select("[data-home-section=checklists-season] .mg-season-title").map { |title| title.text.strip }
      assert_includes titles, "Concessions"
      assert_not_includes titles, "Concession shifts", "the Trip line says it all"
      assert_includes titles, "Build", "two items can't fit on one line"
      assert_select "[data-home-section=checklists-season] .mg-season-item a[href=?]", checklist_path(concessions)
    end
  end

  test "another checklist's line is no to-do of its own when that checklist's rows are there" do
    concessions = create_world_checklist("Concessions")
    add_rule(concessions, :include, :person, person_id: person(:member).id)
    add_item(concessions, :plain, "Shifts")
    add_item(@checklist, :checklist, "Concessions", { checklist_id: concessions.id })
    refresh(concessions)
    refresh(@checklist)

    with_feature_on do
      sign_in person(:member).user
      get root_path
      assert_select "[data-home-column=todo] .mg-row", 1
      assert_select "[data-home-column=todo] a[href='/forms']", text: "Fill out"
      assert_select "[data-home-column=todo] a[href=?]", checklist_path(concessions), false
    end
  end

  test "a checklist with everything finished stays in My Season" do
    add_item(@checklist, :has_login, "Login")
    refresh(@checklist)

    with_feature_on do
      sign_in person(:member).user
      get root_path

      assert_select "[data-home-column=todo]", false
      assert_equal [ "Login ✓ Complete" ], season_lines("done")
    end
  end

  test "an ended checklist is no to-do and not in My Season" do
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
    add_item(@checklist, :signed, "Consent")
    add_rule(@checklist, :include, :person, person_id: person(:parent).id)
    refresh(@checklist)

    with_feature_on do
      sign_in person(:parent).user
      get root_path

      label = "for #{person(:kid).identifier_name}"
      assert_select "[data-home-column=todo] .mg-row-ward", text: label
      assert_select "[data-home-column=todo] a.btn", text: "Confirm for #{person(:kid).identifier_name}"
      assert_select "[data-home-section=checklists-season] .mg-season-person-name", text: person(:kid).identifier_name
      assert_select "[data-home-section=checklists-season] .mg-row-ward", false, "the block names the person"
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
      assert_select "[data-home-column=todo] a[href=?]", checklist_path(prereq), text: "Ask a leader"
    end
  end

  test "an organizer sees Checklists once, in the top run; a plain member manages nothing" do
    with_settings(feature_my_gatherpack: "true", feature_checklists: "true", checklists_organizers: "Checklist Organizer > Club") do
      sign_in person(:organizer).user
      menu = MyGatherpack::Menu.new(person(:organizer).user)
      assert menu.manages_anything?
      assert_includes menu.top.map(&:path), :checklists_path
      assert_not_includes menu.manage.map(&:path), :checklists_path

      assert_not MyGatherpack::Menu.new(person(:member).user).manages_anything?
    end
  end

  test "a team manager sees Checklists once, in the top run, not in Manage or under a section heading" do
    with_feature_on do
      menu = MyGatherpack::Menu.new(person(:club_manager).user)
      assert_includes menu.top.map(&:path), :checklists_path
      assert_not_includes menu.manage.map(&:path), :checklists_path
      assert_not_includes menu.sections.flat_map(&:last).map(&:path), :checklists_path
    end
  end

  test "a guardian with two wards sees a block per person, each with its own lines" do
    second = create_world_person("Zed", @members, birthday: Date.new(2015, 5, 1))
    Relationship.create!(parent: person(:parent), child: second, relationship_type: @parent_of, created_by: person(:admin))
    add_rule(@checklist, :include, :person, person_id: person(:parent).id)
    add_rule(@checklist, :include, :person, person_id: second.id)
    add_item(@checklist, :signed, "Consent")
    add_item(@checklist, :waiting, "Paperwork")
    refresh(@checklist)

    with_feature_on do
      sign_in person(:parent).user
      get root_path

      blocks = css_select("[data-season-person]")
      assert_equal [ "You", "Kid", "Zed" ], blocks.map { |block| block.at_css(".mg-season-person-name").text.strip }
      assert_equal [ person(:parent).id, person(:kid).id, second.id ], blocks.map { |block| block["data-season-person"] }
      blocks.each do |block|
        assert_equal [ "Paperwork Not Started" ], block.css("[data-season-group=in-progress] summary").map { |line| line.text.squish }
        assert_equal [ "Consent ✓ Signed" ], block.css("[data-season-group=done] summary").map { |line| line.text.squish }
      end
      assert_select "[data-home-section=checklists-season] .mg-row-ward", false
      assert_select "[data-season-person=?] a[href=?]", second.id, person_checklists_path(second), text: "Zed's checklists"
      assert_select "[data-season-person=?] a[href=?]", person(:parent).id, checklist_path(@checklist)
    end
  end

  test "each person's Done collapses on its own, and each says whether they're all set" do
    add_rule(@checklist, :include, :person, person_id: person(:parent).id)
    add_item(@checklist, :signed, "Consent")
    refresh(@checklist)
    Membership.where(person: person(:kid)).destroy_all

    with_feature_on do
      sign_in person(:parent).user
      get root_path

      targets = css_select("button.mg-season-done").map { |button| button["aria-controls"] }
      assert_equal 2, targets.size
      assert_equal targets.uniq, targets
      targets.each { |id| assert_select "##{id}.collapse details", 1 }
      assert_equal 2, css_select(".mg-season-all-set").size
      assert_select "[data-season-person=?] .mg-season-all-set", person(:kid).id, text: "You're all set for now"
    end
  end

  test "a viewer with only their own lines sees no person headings" do
    add_item(@checklist, :signed, "Consent")
    refresh(@checklist)

    with_feature_on do
      sign_in person(:member).user
      get root_path

      assert_select "[data-home-section=checklists-season] details", 1
      assert_select ".mg-season-person", false
      assert_select ".mg-season-person-name", false
    end
  end

  private

  # A My Season group's lines as they read: title, then the answer.
  def season_lines(group)
    css_select("[data-season-group=#{group}] summary").map { |line| line.text.squish }
  end

  def with_feature_on(&block)
    with_settings(feature_my_gatherpack: "true", feature_checklists: "true", &block)
  end
end
