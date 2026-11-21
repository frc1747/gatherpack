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

  test "page_header shows the title, summary, state and tabs" do
    render "shared/page_header", title: "Field trip permission", summary: "Asks Northwind Robotics",
      state: state_line("Taking answers"), tabs: [ [ "Details", "/forms/1/edit" ], [ "Questions (6)", "/forms/1/questions" ] ]

    assert_select ".card-header h1", text: "Field trip permission"
    assert_select ".card-header .text-muted", text: "Asks Northwind Robotics"
    assert_select ".card-header .screen-state-line", text: "Taking answers"
    assert_select ".card-header ul.nav.nav-underline a.nav-link", 2
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
end
