require "test_helper"

class ScreenKitHelperTest < ActionView::TestCase
  def action_row(*actions)
    render "shared/action_row", actions: actions
  end

  def more_items
    css_select(".dropdown-menu li:not(.d-md-none)")
  end

  test "screen_action builds an action with the kit's defaults" do
    action = screen_action("Edit", "/badges/1/edit", style: :warning)

    assert_equal "Edit", action.label
    assert_equal :warning, action.style
    assert action.get?
    assert action.visible?
    assert_not action.lifecycle?
    assert_not action.destructive?
    assert_not action.more?
  end

  test "three actions show three buttons and no More" do
    action_row screen_action("Edit", "/a", style: :warning), screen_action("Remind", "/b", style: :primary), screen_action("Duplicate", "/c")

    assert_select ".screen-action-row > a.btn", 3
    assert_select ".screen-action-row > a.btn-warning", text: "Edit"
    # The only More is the phone one, holding the two buttons hidden there.
    assert_select ".dropdown:not(.d-md-none)", 0
    assert_select ".dropdown.d-md-none li.d-md-none", 2
  end

  test "five actions show two buttons and a More holding three, Delete last" do
    action_row screen_action("Edit", "/a", style: :warning),
      screen_action("Delete", "/e", method: :delete, destructive: true, confirm: "Delete this form?"),
      screen_action("Remind", "/b", style: :primary),
      screen_action("Preview", "/c"),
      screen_action("Duplicate", "/d")

    assert_select ".screen-action-row > a.btn", 2
    assert_select ".screen-action-row > a.btn", text: "Edit"
    assert_select ".screen-action-row > a.btn", text: "Remind"
    assert_select ".dropdown:not(.d-md-none) > button.btn.btn-secondary.dropdown-toggle", text: "More"
    assert_select ".dropdown-menu.dropdown-menu-end"
    assert_equal [ "Preview", "Duplicate", "Delete" ], more_items.map { |li| li.text.strip }
    assert_select ".dropdown-menu li:last-child .dropdown-item.text-danger", text: "Delete"
  end

  test "More holds ordinary actions, then lifecycle actions, then destructive ones" do
    action_row screen_action("Delete", "/x", method: :delete, destructive: true, confirm: "Delete this sheet?"),
      screen_action("Archive", "/archive", method: :post, lifecycle: true, confirm: "Archive this sheet? It's hidden from lists; sign-ups are kept."),
      screen_action("Edit", "/a", style: :warning),
      screen_action("Sign up", "/b", style: :primary),
      screen_action("Duplicate", "/c"),
      screen_action("Restore", "/restore", method: :post, lifecycle: true, confirm: "Restore this sheet? It shows in lists again.")

    assert_equal [ "Duplicate", "Archive", "Restore", "Delete" ], more_items.map { |li| li.text.strip }
    assert_select ".dropdown-menu form[data-turbo-confirm^='Archive this sheet?'] button.dropdown-item:not(.text-danger)", text: "Archive"
    assert_select ".dropdown-menu .text-danger", 1
  end

  test "with three actions or fewer, Delete is the last button, in red" do
    action_row screen_action("Delete", "/x", method: :delete, destructive: true, confirm: "Delete this badge?"),
      screen_action("Edit", "/a", style: :warning)

    buttons = css_select(".screen-action-row > a.btn, .screen-action-row > form > button.btn")
    assert_equal [ "Edit", "Delete" ], buttons.map { |button| button.text.strip }
    assert_includes buttons.last["class"], "btn-danger"
    assert_select ".dropdown:not(.d-md-none)", 0
  end

  test "Archive goes in More even with three actions or fewer, and Delete follows it there" do
    action_row screen_action("Delete", "/x", method: :delete, destructive: true, confirm: "Delete this sheet?"),
      screen_action("Edit", "/a", style: :warning),
      screen_action("Archive", "/archive", method: :post, lifecycle: true, confirm: "Archive this sheet? It's hidden from lists; sign-ups are kept.")

    buttons = css_select(".screen-action-row > a.btn, .screen-action-row > form > button.btn")
    assert_equal [ "Edit" ], buttons.map { |button| button.text.strip }
    assert_select ".dropdown:not(.d-md-none) > button.dropdown-toggle", text: "More"
    assert_equal [ "Archive", "Delete" ], more_items.map { |li| li.text.strip }
    assert_select ".dropdown-menu li:last-child .dropdown-item.text-danger", text: "Delete"
  end

  test "Restore alone with Edit still makes a More" do
    action_row screen_action("Edit", "/a", style: :warning),
      screen_action("Restore", "/restore", method: :post, lifecycle: true, confirm: "Restore this sheet? It shows in lists again.")

    assert_select ".screen-action-row > a.btn", 1
    assert_equal [ "Restore" ], more_items.map { |li| li.text.strip }
  end

  test "more: true puts an ordinary action in More, before lifecycle and destructive ones" do
    action = screen_action("Mark all brought", "/brought", method: :post, more: true)
    assert action.more?
    assert_not screen_action("Edit", "/a").more?

    action_row screen_action("Edit", "/a", style: :warning), action,
      screen_action("Delete", "/x", method: :delete, destructive: true, confirm: "Delete this list?")

    buttons = css_select(".screen-action-row > a.btn, .screen-action-row > form > button.btn")
    assert_equal [ "Edit" ], buttons.map { |button| button.text.strip }
    assert_equal [ "Mark all brought", "Delete" ], more_items.map { |li| li.text.strip }
  end

  test "more: true keeps the first two other ordinary actions as buttons" do
    action_row screen_action("Edit", "/a", style: :warning), screen_action("Mark all brought", "/brought", method: :post, more: true),
      screen_action("Sign up", "/b", style: :primary), screen_action("Duplicate", "/c")

    buttons = css_select(".screen-action-row > a.btn, .screen-action-row > form > button.btn")
    assert_equal [ "Edit", "Sign up" ], buttons.map { |button| button.text.strip }
    assert_equal [ "Mark all brought", "Duplicate" ], more_items.map { |li| li.text.strip }
  end

  test "an action that isn't visible is left out" do
    action_row screen_action("Edit", "/a", style: :warning), screen_action("Delete", "/x", method: :delete, destructive: true, visible: false)

    assert_select ".screen-action-row > a.btn", 1
    assert_no_match "Delete", rendered
    assert_select ".dropdown", 0
  end

  test "a row with no visible actions renders nothing" do
    action_row screen_action("Edit", "/a", visible: false)

    assert_select ".screen-action-row", 0
  end

  test "a destructive action with a confirm renders button_to with data-turbo-confirm" do
    action_row screen_action("Edit", "/a"), screen_action("Remind", "/b"), screen_action("Copy", "/c"),
      screen_action("Delete", "/forms/1", method: :delete, destructive: true, confirm: "Delete this form and its 12 answers?")

    assert_select ".dropdown-menu form.button_to[action='/forms/1'][data-turbo-confirm='Delete this form and its 12 answers?']" do
      assert_select "input[name=_method][value=delete]", 1
      assert_select "button.dropdown-item.text-danger", text: "Delete"
    end
  end

  test "state_line shows the state in words" do
    render html: state_line("Taking answers until Nov 30")

    assert_select ".screen-state-line.text-muted", text: "Taking answers until Nov 30"
    assert_select ".screen-state-line a", 0
  end

  test "state_line links to the setting when given one" do
    render html: state_line("Not taking answers yet", link_text: "Start taking answers", link_path: "/forms/1/edit")

    assert_select ".screen-state-line", text: /Not taking answers yet/
    assert_select ".screen-state-line a[href='/forms/1/edit']", text: "Start taking answers"
  end

  test "page_header shows the title, summary, state and tabs past two parts" do
    render "shared/page_header", title: "Field trip permission", summary: "Asks Northwind Robotics",
      state: state_line("Taking answers"),
      tabs: [ [ "Details", "/forms/1/edit" ], [ "Questions (6)", "/forms/1/questions" ], [ "Who is asked (24)", "/forms/1/audience" ] ]

    assert_select ".card-header h1", text: "Field trip permission"
    assert_select ".card-header .text-muted", text: "Asks Northwind Robotics"
    assert_select ".card-header .screen-state-line", text: "Taking answers"
    assert_select ".card-header ul.nav.nav-underline a.nav-link", 3
  end

  test "page_header shows no tabs for two parts" do
    render "shared/page_header", title: "Field trip permission",
      tabs: [ [ "Details", "/forms/1/edit" ], [ "Questions (6)", "/forms/1/questions" ] ]

    assert_select ".card-header h1", text: "Field trip permission"
    assert_select ".nav", 0
  end

  test "inline_confirm selects the default choice" do
    render "shared/inline_confirm", question: "3 people have answered. Change their answers too?",
      name: "apply_to_answers", choices: [ [ "No, keep them", "no" ], [ "Yes", "yes" ] ], selected: "no"

    assert_select "p", text: "3 people have answered. Change their answers too?"
    assert_select "input[type=radio][name=apply_to_answers]", 2
    assert_select "input[type=radio][name=apply_to_answers][value=no][checked]", 1
    assert_select "input[type=radio][name=apply_to_answers][value=yes][checked]", 0
    assert_select "label[for=apply_to_answers_no]", text: "No, keep them"
  end

  test "people_table shows the empty line when nobody is in it" do
    render "shared/people_table", rows: []

    assert_select "table", 0
    assert_select "p.text-muted", text: "Nobody here."
  end

  test "people_table links each person and shows the caller's columns" do
    person = Person.create!(first_name: "Nadia", last_name: "Northwind")
    row = Struct.new(:person, :status, :due).new(person, "Complete", "Nov 30")

    render "shared/people_table", rows: [ row ], status: ->(r) { tag.span(r.status, class: "badge") }, columns: [ [ "Due", ->(r) { r.due } ] ]

    assert_select ".table-responsive table thead th", count: 3
    assert_select "tr##{dom_id(person)} td a[href='#{person_path(person)}']", text: person.identifier_name
    assert_select "td .badge", text: "Complete"
    assert_select "td", text: "Nov 30"
  end

  test "empty_state shows the line and a button to add the first one" do
    render "shared/empty_state", text: "Nothing here yet.", action: screen_action("New Checklist", "/checklists/new", style: :success)

    assert_select "p.text-muted", text: "Nothing here yet."
    assert_select "a.btn.btn-success[href='/checklists/new']", text: "New Checklist"
  end

  test "filter_bar shows status pills with counts and table actions at the right" do
    teams = [ Team.new(id: SecureRandom.uuid, name: "Northwind"), Team.new(id: SecureRandom.uuid, name: "Northwind Juniors") ]
    render "shared/filter_bar", url: "/forms/1", teams: teams, team: nil, status: "waiting",
      statuses: [ { label: "All", count: 24, value: nil }, { label: "Complete", count: 18, value: "complete" },
                  { label: "Waiting", count: 6, value: "waiting" }, { label: "Excused", count: 0, value: "excused" } ],
      more: "<input name='since'>".html_safe,
      table_actions: [ screen_action("Print", "/forms/1/print", style: :dark), screen_action("Download CSV", "/forms/1.csv") ]

    assert_select "form[method=get][action='/forms/1'] select[name=team_id] option", 3
    assert_select "form input[type=hidden][name=status][value=waiting]"
    assert_select "form details summary", text: "More choices"
    assert_select "form details input[name=since]"
    assert_select "a.btn-sm.btn-outline-secondary", text: "All (24)"
    assert_select "a.btn-sm.btn-secondary[href='/forms/1?status=waiting']", text: "Waiting (6)"
    assert_no_match "Excused", rendered
    assert_select ".ms-auto a.btn-dark", text: "Print"
    assert_select ".ms-auto a.btn-secondary", text: "Download CSV"
  end

  test "filter_bar keeps the page's other options in the pills and the Show button" do
    teams = [ Team.new(id: SecureRandom.uuid, name: "Northwind"), Team.new(id: SecureRandom.uuid, name: "Northwind Juniors") ]
    render "shared/filter_bar", url: "/forms/1", teams: teams, team: teams.last, status: "waiting",
      params: { since: "2026-11-01", columns: [ "due", "version" ] },
      statuses: [ { label: "All", count: 24, value: nil }, { label: "Complete", count: 18, value: "complete" } ]

    complete = css_select("a").find { |a| a.text == "Complete (18)" }
    assert_equal "/forms/1", complete["href"].split("?").first
    assert_equal({ "since" => "2026-11-01", "columns" => [ "due", "version" ], "team_id" => teams.last.id, "status" => "complete" },
      Rack::Utils.parse_nested_query(complete["href"].split("?").last))
    all = Rack::Utils.parse_nested_query(css_select("a").find { |a| a.text == "All (24)" }["href"].split("?").last)
    assert_not all.key?("status")
    assert_equal "2026-11-01", all["since"]

    assert_select "form[action='/forms/1']" do
      assert_select "input[type=hidden][name=since][value='2026-11-01']"
      assert_select "input[type=hidden][name='columns[]']", 2
      assert_select "input[type=submit][value=Show].btn.btn-secondary"
    end
    assert_select "input[type=submit][value=Filter]", 0
  end

  test "filter_bar merges into a url that already has a query" do
    render "shared/filter_bar", url: "/forms/1?tab=results", status: nil,
      params: { since: "2026-11-01" }, more: "<input name='since'>".html_safe,
      statuses: [ { label: "All", count: 24, value: nil }, { label: "Waiting", count: 6, value: "waiting" } ]

    waiting = css_select("a").find { |a| a.text == "Waiting (6)" }["href"]
    assert_equal "/forms/1", waiting.split("?").first
    assert_equal({ "tab" => "results", "since" => "2026-11-01", "status" => "waiting" }, Rack::Utils.parse_nested_query(waiting.split("?").last))
    assert_equal 1, waiting.count("?")

    assert_select "form[action='/forms/1'] input[type=hidden][name=tab][value=results]"
  end

  test "filter_bar's More choices is closed unless told to start open" do
    render "shared/filter_bar", url: "/forms/1", more: "<input name='since'>".html_safe
    assert_select "details:not([open])", 1

    render "shared/filter_bar", url: "/forms/1", more: "<input name='since' value='2026-11-01'>".html_safe, open: true
    assert_select "details[open]", 1
  end

  test "filter_bar's hidden: is what Show keeps, while the pills keep params:" do
    teams = [ Team.new(id: SecureRandom.uuid, name: "Northwind"), Team.new(id: SecureRandom.uuid, name: "Northwind Juniors") ]
    render "shared/filter_bar", url: "/forms/1?tab=results", teams: teams, team: teams.first, status: "waiting",
      params: { totals: "hidden", columns: [ "due", "version" ] }, hidden: { totals: "hidden" },
      more: "<input type='checkbox' name='columns[]' value='due' checked>".html_safe,
      statuses: [ { label: "All", count: 24, value: nil }, { label: "Waiting", count: 6, value: "waiting" } ]

    waiting = Rack::Utils.parse_nested_query(css_select("a").find { |a| a.text == "Waiting (6)" }["href"].split("?").last)
    assert_equal({ "tab" => "results", "totals" => "hidden", "columns" => [ "due", "version" ], "team_id" => teams.first.id, "status" => "waiting" }, waiting)

    assert_select "form[action='/forms/1']" do
      assert_select "input[type=hidden][name=totals][value=hidden]"
      assert_select "input[type=hidden][name=tab][value=results]"
      assert_select "input[type=hidden][name=status][value=waiting]"
      assert_select "input[type=hidden][name='columns[]']", 0
      assert_select "details input[type=checkbox][name='columns[]']", 1
    end
  end

  test "filter_bar takes non-link table controls, a form id and its own blank team choice" do
    teams = [ Team.new(id: SecureRandom.uuid, name: "Northwind"), Team.new(id: SecureRandom.uuid, name: "Northwind Juniors") ]
    render "shared/filter_bar", url: "/forms/1", teams: teams, form_id: "form-options", all_teams_label: "All of Northwind",
      table_actions_html: tag.button("Print", type: "button", class: "btn btn-dark", data: { action: "form-results#print" }),
      table_actions: [ screen_action("Download CSV", "/forms/1.csv") ]

    assert_select "form#form-options select[name=team_id] option:first-child", text: "All of Northwind"
    assert_select ".screen-table-actions > button.btn-dark[data-action='form-results#print']", text: "Print"
    assert_select ".screen-table-actions > button + a.btn-secondary", text: "Download CSV"
    assert_select "form .screen-table-actions", 0
  end

  test "filter_bar shows a table control slot with no link actions" do
    render "shared/filter_bar", url: "/forms/1", table_actions_html: tag.button("Print", type: "button", class: "btn btn-dark")
    assert_select ".screen-table-actions button", text: "Print"

    render "shared/filter_bar", url: "/forms/1"
    assert_select ".screen-table-actions", 0
  end

  test "people_table takes table classes, wrapper options, column options and rows after" do
    person = Person.create!(first_name: "Nadia", last_name: "Northwind")
    other = Person.create!(first_name: "Omar", last_name: "Northwind")
    row = Struct.new(:person, :allergy).new(person, "Peanuts")

    render "shared/people_table", rows: [ row ], link: ->(r) { "/forms/1/responses/#{r.person.id}" },
      table_class: "table table-striped table-sm align-middle",
      wrapper: { id: "responses", class: "d-print-none", data: { form_results_target: "table" } },
      columns: [ [ "Allergies", ->(r) { r.allergy }, { class: "table-info" } ] ],
      rows_after: tag.tr(tag.td("Omar Northwind"), id: dom_id(other))

    assert_select "div.table-responsive.d-print-none#responses[data-form-results-target=table] table.table-sm"
    assert_select "th.table-info", text: "Allergies"
    assert_select "tr##{dom_id(person)} td.table-info", text: "Peanuts"
    assert_select "tr##{dom_id(person)} td a[href='/forms/1/responses/#{person.id}']", text: person.identifier_name
    assert_select "tbody tr:last-child##{dom_id(other)}", text: "Omar Northwind"
  end

  test "people_table shows rows after even with no rows, and a nil link is plain text" do
    person = Person.create!(first_name: "Nadia", last_name: "Northwind")
    render "shared/people_table", rows: [], rows_after: tag.tr(tag.td("Omar Northwind"))
    assert_select "table tbody tr", text: "Omar Northwind"
    assert_select "p.text-muted", 0

    render "shared/people_table", rows: [ Struct.new(:person).new(person) ], link: ->(_) { nil }
    assert_select "tr##{dom_id(person)} td", text: person.identifier_name
    assert_select "tr##{dom_id(person)} td a", 0
  end

  test "people_table with link: nil shows plain names" do
    person = Person.create!(first_name: "Nadia", last_name: "Northwind")
    render "shared/people_table", rows: [ Struct.new(:person).new(person) ], link: nil

    assert_select "tr##{dom_id(person)} td", text: person.identifier_name
    assert_select "tr##{dom_id(person)} td a", 0
  end

  test "screen_action passes data: to the link and to button_to's button" do
    action_row screen_action("Edit", "/a", style: :warning, data: { turbo_frame: "_top" }),
      screen_action("Copy", "/c", method: :post, data: { controller: "copy" }, confirm: "Copy this list?")

    assert_select ".screen-action-row > a.btn[href='/a'][data-turbo-frame=_top]", text: "Edit"
    assert_select ".screen-action-row > form[data-turbo-confirm='Copy this list?'] > button.btn[data-controller=copy]", text: "Copy"
    assert_select "a[data-turbo-confirm]", 0
  end

  test "an action with no path is a plain button, as a row button and as a More item" do
    print = screen_action("Print", nil, style: :dark, data: { action: "form-results#print" })
    assert print.script?
    assert_not screen_action("Edit", "/a").script?

    action_row screen_action("Edit", "/a", style: :warning), print
    assert_select ".screen-action-row > button.btn.btn-dark[type=button][data-action='form-results#print']", text: "Print"
    assert_select ".screen-action-row form", 0

    action_row screen_action("Edit", "/a", style: :warning), screen_action("Print", nil, data: { action: "form-results#print" }, more: true)
    assert_select ".dropdown-menu li:not(.d-md-none) > button.dropdown-item[type=button][data-action='form-results#print']", text: "Print"
  end

  test "a filter bar takes a plain-button action among its table actions" do
    render "shared/filter_bar", url: "/forms/1",
      table_actions: [ screen_action("Print", nil, style: :dark, data: { action: "form-results#print" }), screen_action("Download CSV", "/forms/1.csv") ]

    assert_select ".screen-table-actions > button.btn-dark[type=button][data-action='form-results#print']", text: "Print"
    assert_select ".screen-table-actions > a.btn-secondary[href='/forms/1.csv']", text: "Download CSV"
  end

  test "filter_bar shows fields before the pills, inside the Show form" do
    render "shared/filter_bar", url: "/seasons", fields: select_tag(:season, options_for_select([ "2026", "2025" ]), class: "form-select"),
      statuses: [ { label: "All", count: 3, value: nil }, { label: "Open", count: 1, value: "open" } ]

    assert_select "form[action='/seasons'] select[name=season] option", 2
    assert_select "form input[type=submit][value=Show]:not([data-filter-bar-target])"
    assert_select "form[data-controller]", 0
    fields_then_pills = css_select("select[name=season], .screen-filter-pills a").map(&:name)
    assert_equal [ "select", "a", "a" ], fields_then_pills
  end

  test "filter_bar's auto_submit wires the form to submit on change, keeping Show for no JavaScript" do
    render "shared/filter_bar", url: "/seasons", fields: select_tag(:season, options_for_select([ "2026", "2025" ])), auto_submit: true

    assert_select "form[data-controller=filter-bar][data-action='change->filter-bar#submit']" do
      assert_select "input[type=submit][value=Show][data-filter-bar-target=show]:not([hidden])"
    end
  end
end
