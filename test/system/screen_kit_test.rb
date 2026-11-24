require "application_system_test_case"

class ScreenKitTest < ApplicationSystemTestCase
  include Devise::Test::IntegrationHelpers

  PHONE = [ 390, 800 ].freeze

  setup do
    # config.hosts allows localhost, not Capybara's default 127.0.0.1.
    @always_include_port = Capybara.always_include_port
    Capybara.app_host = "http://localhost"
    Capybara.always_include_port = true

    @path = Rails.root.join("tmp", "screen-kit-system-test-#{Process.pid}.pstore").to_s
    File.delete(@path) if File.exist?(@path)
    @original_store = Settings.instance.store
    Settings.instance.store = PStore.new(@path, true)

    @user = User.create!(email: "admin@example.com", password: "Password1!", admin: true)
    Person.create!(user: @user, first_name: "Nadia", last_name: "Northwind")
    sign_in @user
  end

  teardown do
    page.driver.browser.manage.window.resize_to(1400, 1400)
    Settings.instance.store = @original_store
    File.delete(@path) if File.exist?(@path)
    Capybara.app_host = nil
    Capybara.always_include_port = @always_include_port
  end

  test "at phone width only the first action and More show, and More holds the rest" do
    page.driver.browser.manage.window.resize_to(*PHONE)
    visit new_badge_type_path
    add_action_row [ [ "Edit", "/edit", :warning ], [ "Remind", "/remind", :primary ], [ "Duplicate", "/copy", :secondary ],
                     [ "Preview", "/preview", :secondary ], [ "Delete", "/delete", :secondary, true ] ]

    within "#kit-row" do
      assert_equal [ "Edit", "More" ], all(".btn", visible: true).map(&:text)
      click_on "More"
      assert_equal [ "Remind", "Duplicate", "Preview", "Delete" ], all(".dropdown-item", visible: true).map(&:text)
    end
  end

  test "at desktop width the row shows two actions and More holds the rest" do
    visit new_badge_type_path
    add_action_row [ [ "Edit", "/edit", :warning ], [ "Remind", "/remind", :primary ], [ "Duplicate", "/copy", :secondary ],
                     [ "Preview", "/preview", :secondary ], [ "Delete", "/delete", :secondary, true ] ]

    within "#kit-row" do
      assert_equal [ "Edit", "Remind", "More" ], all(".btn", visible: true).map(&:text)
      click_on "More"
      assert_equal [ "Duplicate", "Preview", "Delete" ], all(".dropdown-item", visible: true).map(&:text)
    end
  end

  test "with the feature on, menu items on a touch screen are at least 44px tall" do
    Settings[:feature_screen_standard] = "true"
    page.driver.browser.manage.window.resize_to(*PHONE)
    emulate_touch
    visit new_badge_type_path
    assert evaluate_script("matchMedia('(pointer: coarse)').matches")
    add_action_row [ [ "Edit", "/edit", :warning ], [ "Archive", "/archive", :secondary ], [ "Duplicate", "/copy", :secondary ],
                     [ "Delete", "/delete", :secondary, true ] ]

    within "#kit-row" do
      click_on "More"
      heights = all(".dropdown-item", visible: true).map { |item| evaluate_script("arguments[0].getBoundingClientRect().height", item) }
      assert_equal 3, heights.size
      heights.each { |height| assert_operator height, :>=, 44 }
    end
  ensure
    emulate_touch(false)
  end

  test "with a mouse, menu items keep Bootstrap's compact size" do
    Settings[:feature_screen_standard] = "true"
    visit new_badge_type_path
    assert_not evaluate_script("matchMedia('(pointer: coarse)').matches")
    add_action_row [ [ "Edit", "/edit", :warning ], [ "Remind", "/remind", :primary ], [ "Duplicate", "/copy", :secondary ],
                     [ "Delete", "/delete", :secondary, true ] ]

    within "#kit-row" do
      click_on "More"
      heights = all(".dropdown-item", visible: true).map { |item| evaluate_script("arguments[0].getBoundingClientRect().height", item) }
      heights.each { |height| assert_operator height, :<, 44 }
    end
  end

  test "with the feature on, an upstream form's Cancel takes the secondary colour" do
    Settings[:feature_screen_standard] = "true"
    visit edit_badge_path(badges(:one))

    assert_equal button_colour("btn-secondary"), background_of("main form .card-footer > a", text: "Cancel")
    assert_not_equal button_colour("btn-warning"), background_of("main form .card-footer > a", text: "Cancel")
  end

  test "with the feature off, an upstream form's Cancel stays yellow" do
    visit edit_badge_path(badges(:one))

    assert_equal button_colour("btn-warning"), background_of("main form .card-footer > a", text: "Cancel")
  end

  # mailboxes/show's footer: Edit sits after a search submit, not before one.
  # (The page itself raises a Ransack error on upstream, so its footer is
  # copied onto another page.)
  test "with the feature on, Edit beside a search submit keeps its yellow" do
    Settings[:feature_screen_standard] = "true"
    visit edit_badge_path(badges(:one))
    execute_script(<<~JS)
      document.querySelector("main").insertAdjacentHTML("afterbegin", `
        <form id="mailbox-search" method="get"><div class="card"><div class="card-footer">
          <a href="#" class="btn btn-success">New Message</a>
          <input type="submit" name="commit" value="Search Messages" class="btn btn-primary">
          <a href="#" class="btn btn-dark">Clear Search</a>
          <a href="#" class="btn btn-warning">Edit</a>
          <a href="#" class="btn btn-danger">Delete</a>
        </div></div></form>`)
    JS

    assert_equal button_colour("btn-warning"), background_of("#mailbox-search .card-footer > a", text: "Edit")
    assert_equal button_colour("btn-secondary"), background_of("main form:not(#mailbox-search) .card-footer > a", text: "Cancel")
  end

  test "an auto-submitting filter bar hides Show and shows a new choice at once" do
    visit badge_types_path
    add_filter_bar auto_submit: true
    within "#kit-filter" do
      assert_no_button "Show"
      select "2025", from: "season"
    end
    assert_current_path badge_types_path(season: "2025")
  end

  test "a filter bar's More choices apply as soon as they change, and keep a Show of their own" do
    visit badge_types_path
    add_filter_bar auto_submit: true, more: "<label><input type='checkbox' name='late' value='1'> Late</label>".html_safe
    within "#kit-filter" do
      assert_button "Show", count: 1
      find("summary").click
      assert_button "Show", count: 2
      check "Late"
    end
    assert_current_path "#{badge_types_path}?season=2026&late=1"
  end

  test "without auto_submit, top-row fields wait for Show while More choices apply at once" do
    visit badge_types_path
    add_filter_bar more: "<label>Since <input type='text' name='since'></label>".html_safe
    within "#kit-filter" do
      select "2025", from: "season"
      find("summary").click
      fill_in "Since", with: "2026-11-01"
    end
    assert_current_path badge_types_path
    find("#kit-filter summary").click
    assert_current_path "#{badge_types_path}?season=2025&since=2026-11-01"
  end

  test "the column chooser hides a column, remembers it, and keeps Person and the last column" do
    visit badge_types_path
    execute_script("localStorage.clear()")
    add_people_table
    within "#kit-table" do
      click_on "Columns"
      assert_equal [ "Status", "Allergies", "Notes" ], all(".dropdown-menu label").map(&:text)
      uncheck "Allergies"
      uncheck "Notes"
      assert_no_selector "th", text: "Allergies"
      assert_no_selector "th", text: "Notes"
      assert_no_selector "td", text: "Peanuts"
      assert_selector "th", text: "Status"
      assert_selector "td", text: "Nadia Northwind"
      assert_field "Status", checked: true, disabled: true
    end

    visit badge_types_path
    add_people_table
    within "#kit-table" do
      assert_selector "th", text: "Status"
      assert_no_selector "th", text: "Allergies"
      assert_no_selector "td", text: "Peanuts"
      click_on "Columns"
      check "Allergies"
      assert_selector "td", text: "Peanuts"
      assert_field "Status", checked: true, disabled: false
    end
  end

  test "the column chooser goes in a filter bar's table actions when the wrapper holds both" do
    visit badge_types_path
    execute_script("localStorage.clear()")
    filter = ApplicationController.render(partial: "shared/filter_bar", locals: { url: badge_types_path, status: nil })
    add_people_table(before: filter, wrapper: ApplicationController.helpers.column_chooser_data("kit-people"))
    within "#kit-table .screen-filter-bar" do
      assert_selector ".dropdown.ms-auto", text: "Columns"
      click_on "Columns"
      uncheck "Status"
    end
    assert_no_selector "#kit-table th", text: "Status"
  end

  test "one column chooser hides the column in every table inside it" do
    visit badge_types_path
    execute_script("localStorage.clear()")
    add_people_table(wrapper: ApplicationController.helpers.column_chooser_data("kit-sections"), tables: 2)
    within "#kit-table" do
      assert_selector ".dropdown", text: "Columns", count: 1
      click_on "Columns"
      uncheck "Allergies"
      assert_no_selector "th", text: "Allergies"
      assert_no_selector "td", text: "Peanuts"
      assert_selector "td", text: "Nadia Northwind", count: 2
    end
  end

  test "the column chooser keeps stored names that aren't on this page" do
    visit badge_types_path
    execute_script(%q(localStorage.setItem("columns:kit-people", JSON.stringify(["Shirt size"]))))
    add_people_table
    within "#kit-table" do
      click_on "Columns"
      uncheck "Allergies"
    end
    assert_equal [ "Shirt size", "Allergies" ], JSON.parse(evaluate_script(%q(localStorage.getItem("columns:kit-people"))))
  end

  test "applying a choice keeps the page where it was scrolled to" do
    page.driver.browser.manage.window.resize_to(1200, 700)
    visit badge_types_path
    tall = "<div id='kit-tall' style='height: 2000px'></div>"
    execute_script("document.querySelector('main').insertAdjacentHTML('afterbegin', arguments[0])", tall)
    add_filter_bar more: "<label><input type='checkbox' name='late' value='1'> Late</label>".html_safe
    execute_script("document.querySelector('main').append(document.getElementById('kit-filter'))")
    find("#kit-filter summary").click
    execute_script("document.getElementById('kit-filter').scrollIntoView()")
    before = evaluate_script("window.scrollY")
    assert_operator before, :>, 500
    check "Late"
    assert_current_path "#{badge_types_path}?season=2026&late=1"

    # The page that comes back has its own filter bar; the kit's controller
    # restores the place when it connects.
    execute_script("document.querySelector('main').insertAdjacentHTML('afterbegin', arguments[0])", tall)
    add_filter_bar more: "<label><input type='checkbox' name='late' value='1'> Late</label>".html_safe
    after = nil
    20.times do
      after = evaluate_script("window.scrollY")
      break if (after - before).abs <= 5
      sleep 0.05
    end
    assert_in_delta before, after, 5, "height #{evaluate_script('document.documentElement.scrollHeight')}"
  end

  test "changes inside a wait marker under More choices apply only with Show" do
    visit badge_types_path
    add_filter_bar more: <<~HTML.html_safe
      <label><input type="checkbox" name="late" value="1"> Late</label>
      <div data-filter-bar-wait><label>Form <select name="form"><option></option><option>Intake</option></select></label></div>
    HTML
    within "#kit-filter" do
      find("summary").click
      select "Intake", from: "Form"
    end
    assert_current_path badge_types_path
    within("#kit-filter details") { click_on "Show" }
    assert_current_path "#{badge_types_path}?season=2026&form=Intake"
  end

  test "a people table under a filter bar with table actions puts Columns in the bar and keeps Person" do
    visit badge_types_path
    execute_script("localStorage.clear()")
    filter = ApplicationController.render(partial: "shared/filter_bar", locals: {
      url: badge_types_path, status: nil,
      table_actions: [ ScreenKit::Action.new(label: "Download CSV", path: "/people.csv", style: :secondary) ]
    })
    add_people_table(before: filter, wrapper: ApplicationController.helpers.column_chooser_data("kit-people"))
    within "#kit-table .screen-table-actions" do
      assert_selector ":first-child.dropdown > button.btn.btn-secondary.dropdown-toggle", text: "Columns"
      click_on "Columns"
      assert_equal [ "Status", "Allergies", "Notes" ], all(".dropdown-menu label").map(&:text)
      uncheck "Status"
    end
    assert_no_selector "#kit-table th", text: "Status"
    assert_selector "#kit-table th", text: "Person"
    assert_selector "#kit-table .dropdown", text: "Columns", count: 1
  end

  test "clicking a heading sorts its rows, again reverses, and numbers and dates compare as such" do
    add_filter_table [ [ "Ben", "$1,200", "2026-03-01", "Build" ], [ "ana", "$90", "2025-12-24", "Code" ], [ "Cleo", "$5", "2026-01-15", "" ] ],
      after: [ [ "Zed", "$3", "2024-01-01", "Build" ], [ "Abe", "$40", "2027-01-01", "Code" ] ]
    within "#kit-filter-table" do
      find("[role=button]", text: "Name").click
      assert_equal %w[ana Ben Cleo Later Abe Zed], first_cells
      assert_selector "th[aria-sort=ascending] [data-table-filter-arrow] .fa-arrow-up"
      find("[role=button]", text: "Name").click
      assert_equal %w[Cleo Ben ana Later Zed Abe], first_cells
      assert_selector "th[aria-sort=descending] [data-table-filter-arrow] .fa-arrow-down"
      find("[role=button]", text: "Amount").click
      assert_equal %w[Cleo ana Ben Later Zed Abe], first_cells
      find("[role=button]", text: "Due").click
      assert_equal %w[ana Cleo Ben Later Zed Abe], first_cells
      assert_selector "th[aria-sort]", count: 1
    end
  end

  test "ticking values in a heading's funnel shows only rows with any of them" do
    add_filter_table [ [ "Ben", "1", "", "Build" ], [ "Ana", "2", "", "Code" ], [ "Cleo", "3", "", "Build" ], [ "Dev", "4", "", "" ] ]
    within "#kit-filter-table" do
      open_filter "Team"
      assert_equal [ "Build (2)", "Code (1)", "(blank) (1)" ], all("[data-table-filter-menu=Team] label").map(&:text)
      assert_no_selector "[data-table-filter-menu=Team] input[type=search]"
      check "Build (2)"
      assert_equal %w[Ben Cleo Later], first_cells
      assert_selector "[aria-label='Filter Team']:not(.opacity-50)"
      check "(blank) (1)"
      assert_equal %w[Ben Cleo Dev Later], first_cells
      uncheck "Build (2)"
      uncheck "(blank) (1)"
      assert_equal %w[Ben Ana Cleo Dev Later], first_cells
      assert_selector "[aria-label='Filter Team'].opacity-50"
    end
  end

  test "past 12 values the funnel keeps its tick boxes and adds a search box that narrows them" do
    names = %w[Ana Ben Cleo Dev Eli Fay Gus Hal Ida Jon Kai Lea Max]
    add_filter_table names.map { |name| [ name, "1", "", "Build" ] }
    within "#kit-filter-table" do
      open_filter "Name"
      assert_selector "[data-table-filter-menu=Name] label", count: 13
      find("input[aria-label='Search Name']").set("e")
      assert_equal [ "Ben (1)", "Cleo (1)", "Dev (1)", "Eli (1)", "Lea (1)" ], all("[data-table-filter-menu=Name] label", visible: true).map(&:text)
      assert_equal names + [ "Later" ], first_cells
      check "Cleo (1)"
      check "Lea (1)"
      assert_equal %w[Cleo Lea Later], first_cells
      open_filter "Team"
      assert_no_selector "[data-table-filter-menu=Team] input[type=search]"
    end
  end

  test "filters on two columns combine, and Clear filters beside Columns shows every row again" do
    add_filter_table [ [ "Ben", "1", "", "Build" ], [ "Ana", "2", "", "Code" ], [ "Cleo", "1", "", "Code" ] ]
    assert_no_selector "#kit-filter-table a", text: "Clear filters"
    within "#kit-filter-table" do
      open_filter "Team"
      check "Code (2)"
      open_filter "Amount"
      check "1 (2)"
      assert_equal %w[Cleo Later], first_cells
      assert_selector ".dropdown + a", text: "Clear filters"
      click_on "Columns"
      uncheck "Due"
      assert_no_selector "th", text: "Due"
      click_on "Clear filters"
      assert_equal %w[Ben Ana Cleo Later], first_cells
      assert_no_selector "a", text: "Clear filters"
      assert_no_selector "[data-table-filter-tick]:checked", visible: :all
      assert_no_selector "th", text: "Due"
    end
  end

  test "headings over form fields, marked to skip or without text get no funnel and don't sort" do
    add_filter_table [ [ "Ben", "1", "", "Build" ] ], extra: true
    within "#kit-filter-table" do
      assert_selector "[data-table-filter-menu]", count: 4
      assert_no_selector "[aria-label='Filter Bring']"
      assert_no_selector "[aria-label='Filter Notes']"
      assert_no_selector "th:last-child [role=button]"
      find("th", text: "Notes").click
      assert_no_selector "th[aria-sort]"
    end
  end

  test "a wrapper marked data-table-filter off gets no sorting or filtering" do
    add_filter_table [ [ "Ben", "1", "", "Build" ] ], off: true
    within "#kit-filter-table" do
      assert_selector ".dropdown", text: "Columns"
      assert_no_selector "[data-table-filter-menu]"
      assert_no_selector "th [role=button]"
    end
  end

  test "sections in one wrapper share the funnel's values and filter together" do
    add_filter_table [ [ "Ben", "1", "", "Build" ], [ "Ana", "2", "", "Code" ] ], tables: 2
    within "#kit-filter-table" do
      assert_selector "[aria-label='Filter Team']", count: 2
      first("[aria-label='Filter Team']").click
      assert_equal [ "Build (2)", "Code (2)" ], all("[data-table-filter-menu=Team] label", visible: true).map(&:text)
      first("label", text: "Code (2)").check
      assert_equal %w[Ana Later Ana Later], first_cells
      assert_selector "[data-table-filter-tick=Team][value=Code]:checked", count: 2, visible: :all
    end
  end

  test "in a filter bar's table actions, Clear filters follows Columns, and a labelled heading sorts by its label" do
    visit badge_types_path
    execute_script("localStorage.clear()")
    filter = ApplicationController.render(partial: "shared/filter_bar", locals: {
      url: badge_types_path, status: nil,
      table_actions: [ ScreenKit::Action.new(label: "Download CSV", path: "/people.csv", style: :secondary) ]
    })
    add_people_table(before: filter, wrapper: ApplicationController.helpers.column_chooser_data("kit-people"))
    within "#kit-table" do
      open_filter "Allergies"
      check "Peanuts (1)"
      assert_selector ".screen-table-actions .dropdown + a", text: "Clear filters"
      find("th [data-column-chooser-label]", text: "Notes").click
      assert_selector "th[aria-sort=ascending]", text: "Notes"
      assert_selector "th", text: "Person"
      open_filter "Person"
      assert_selector "label", text: "Nadia Northwind (1)"
    end
  end

  test "a heading holding a link or a button keeps its full name for Columns and sorts outside the control" do
    add_filter_table [ [ "Ben", "1", "", "Build" ], [ "Ana", "2", "", "Code" ] ],
      headings: [ '<a href="#by-name">Name</a>'.html_safe, "Amount", "Due", 'Team <button type="button" id="team-help">?</button>'.html_safe ]
    within "#kit-filter-table" do
      assert_no_selector "th:first-child [data-table-filter-label], th:nth-child(4) [data-table-filter-label]"
      assert_selector "th:nth-child(2) [data-table-filter-label][role=button]", text: "Amount"
      click_on "Columns"
      assert_equal [ "Name", "Amount", "Due", "Team ?" ], all("[data-column-chooser-menu] .dropdown-menu label").map(&:text)
      uncheck "Name"
      assert_no_selector "th", text: "Name"
      assert_no_selector "td", text: "Ben"
      check "Name"
      find("#team-help").click
      assert_no_selector "th[aria-sort]"
      execute_script("arguments[0].click()", find("th", text: "Team"))
      assert_selector "th[aria-sort=ascending]", text: "Team"
      assert_equal %w[Ben Ana Later], first_cells
      execute_script("arguments[0].click()", find("th", text: "Name"))
      assert_equal %w[Ana Ben Later], first_cells
      open_filter "Name"
      check "Ben (1)"
      assert_equal %w[Ben Later], first_cells
    end
  end

  test "a row the filter hides leaves its fields out of the form, and gets them back on Clear" do
    add_filter_table [ [ "Ben", "1", "", "Build" ], [ "Ana", "2", "", "Code" ] ], extra: true, form: true
    within "#kit-filter-table" do
      open_filter "Team"
      check "Code (1)"
      assert_equal %w[Ana Later], first_cells
      assert_selector "tr[hidden] input[type=checkbox][disabled]", visible: :all
      click_on "Order"
    end
    assert_current_path "#{badge_types_path}?#{{ "bring" => [ "Ana" ] }.to_query}"
  end

  test "Clear filters gives a hidden row's fields back as they were" do
    add_filter_table [ [ "Ben", "1", "", "Build" ], [ "Ana", "2", "", "Code" ] ], extra: true
    execute_script("document.querySelector('#kit-filter-table tbody input[value=Ana]').disabled = true")
    within "#kit-filter-table" do
      open_filter "Team"
      check "Code (1)"
      click_on "Clear filters"
      assert_selector "tbody input[value=Ben]:not([disabled])"
      assert_selector "tbody input[value=Ana][disabled]"
    end
  end

  test "footer rows hide while any filter is on and come back on Clear" do
    add_filter_table [ [ "Ben", "1", "", "Build" ], [ "Ana", "2", "", "Code" ] ], foot: true
    within "#kit-filter-table" do
      assert_selector "tfoot td", text: "Total"
      open_filter "Team"
      check "Code (1)"
      assert_no_selector "tfoot td", text: "Total"
      click_on "Clear filters"
      assert_selector "tfoot td", text: "Total"
    end
  end

  test "a carry-marked table action takes the heading filters and sort along, and the server gives the rows shown" do
    rows = [ [ "Ben", "1", "2026-03-01", "Build" ], [ "ana", "1", "", "Code" ], [ "Cleo", "1", "2025-01-02", "Build" ],
             [ "Dev", "2", "", "Build" ], [ "Eli", "1", "", "" ] ]
    filter = ApplicationController.render(partial: "shared/filter_bar", locals: {
      url: badge_types_path, status: nil,
      table_actions: [ ScreenKit::Action.new(label: "Download CSV", path: badge_types_path(format_hint: "csv", tf_sort: "Old"), style: :secondary, data: { table_filter_carry: true }) ]
    })
    add_filter_table rows, keys: { "Team" => "team" }, before: filter
    within "#kit-filter-table" do
      open_filter "Team"
      check "Build (3)"
      check "Code (1)"
      open_filter "Amount"
      check "1 (4)"
      find("[role=button]", text: "Name").click
      find("[role=button]", text: "Name").click
      assert_equal %w[Cleo Ben ana Later], first_cells
      click_on "Download CSV"
    end

    assert_current_path(/format_hint=csv/)
    query = current_query
    assert_equal({ "format_hint" => "csv", "tf" => { "team" => [ "Build", "Code" ], "Amount" => "1" }, "tf_sort" => "Name", "tf_dir" => "desc" }, query)

    columns = %w[Name Amount Due team].each_with_index.to_h { |key, index| [ key, ->(row) { row[index] } ] }
    shown = TableFilterParams.new(query["tf"], sort: query["tf_sort"], dir: query["tf_dir"]).apply(rows, columns)
    assert_equal %w[Cleo Ben ana], shown.map(&:first)
  end

  test "after sorting by two headings in a row, ties keep the loaded order and the server gives the same rows" do
    rows = [ [ "Ben", "1", "", "Build" ], [ "ana", "1", "", "Code" ], [ "Cleo", "1", "", "Build" ], [ "Dev", "2", "", "Build" ], [ "Eli", "1", "", "" ] ]
    filter = ApplicationController.render(partial: "shared/filter_bar", locals: {
      url: badge_types_path, status: nil,
      table_actions: [ ScreenKit::Action.new(label: "Download CSV", path: badge_types_path, style: :secondary, data: { table_filter_carry: true }) ]
    })
    add_filter_table rows, before: filter
    within "#kit-filter-table" do
      find("[role=button]", text: "Team").click
      assert_equal %w[Ben Cleo Dev ana Eli Later], first_cells
      find("[role=button]", text: "Amount").click
      assert_equal %w[Ben ana Cleo Eli Dev Later], first_cells
      find("[role=button]", text: "Amount").click
      assert_equal %w[Dev Ben ana Cleo Eli Later], first_cells
      click_on "Download CSV"
    end

    assert_current_path(/tf_sort=Amount/)
    query = current_query
    columns = %w[Name Amount Due Team].each_with_index.to_h { |key, index| [ key, ->(row) { row[index] } ] }
    shown = TableFilterParams.new(query["tf"], sort: query["tf_sort"], dir: query["tf_dir"]).apply(rows, columns)
    assert_equal %w[Dev Ben ana Cleo Eli], shown.map(&:first)
  end

  test "two headings that read the same but carry different keys filter apart, and carry their own keys" do
    rows = [ [ "Ann", "Slim", "Big" ], [ "Bo", "Big", "Slim" ] ]
    filter = ApplicationController.render(partial: "shared/filter_bar", locals: {
      url: badge_types_path, status: nil,
      table_actions: [ ScreenKit::Action.new(label: "Download CSV", path: badge_types_path, style: :secondary, data: { table_filter_carry: true }) ]
    })
    add_filter_table rows, headings: [ "Name", "Sandwich", "Sandwich" ], keys: [ nil, "q1", "q2" ], before: filter
    within "#kit-filter-table" do
      assert_selector "[aria-label='Filter Sandwich']", count: 2
      all("[aria-label='Filter Sandwich']").last.click
      check "Slim (1)"
      assert_equal %w[Bo Later], first_cells
      click_on "Download CSV"
    end

    assert_current_path(/tf/)
    query = current_query
    assert_equal({ "q2" => "Slim" }, query["tf"])
    columns = { "Name" => ->(row) { row[0] }, "q1" => ->(row) { row[1] }, "q2" => ->(row) { row[2] } }
    assert_equal %w[Bo], TableFilterParams.new(query["tf"]).apply(rows, columns).map(&:first)
  end

  test "a carry-marked button sends the filters as fields of its form, and drops them once cleared" do
    form = <<~HTML
      <form action="#{badge_types_path}" method="get">
        <input type="hidden" name="season" value="2026">
        <button type="submit" class="btn btn-secondary" data-table-filter-carry>Labels</button>
      </form>
    HTML
    add_filter_table [ [ "Ben", "1", "", "Build" ], [ "Ana", "2", "", "Code" ] ], before: form
    within "#kit-filter-table" do
      open_filter "Team"
      check "Code (1)"
      find("[role=button]", text: "Due").click
      click_on "Clear filters"
      open_filter "Amount"
      check "1 (1)"
      # Kept on the page, so its fields can be read after each click.
      execute_script("document.querySelector('#kit-filter-table form').addEventListener('submit', (event) => event.preventDefault())")
      click_on "Labels"
      assert_equal [ [ "tf[Amount]", "1" ], [ "tf_sort", "Due" ], [ "tf_dir", "asc" ] ],
        all("form input[data-table-filter-carried]", visible: :all).map { |field| [ field[:name], field[:value] ] }
      click_on "Clear filters"
      click_on "Labels"
      assert_equal [ [ "tf_sort", "Due" ], [ "tf_dir", "asc" ] ],
        all("form input[data-table-filter-carried]", visible: :all).map { |field| [ field[:name], field[:value] ] }
    end
  end

  private

  # Renders shared/_people_table with Status and Allergies columns and adds
  # it to the page; before: HTML put ahead of it, wrapper: data for an outer
  # div around both (else the table carries the chooser itself).
  def add_people_table(before: "", wrapper: nil, tables: 1)
    row = Struct.new(:person, :allergy).new(Person.find_by!(first_name: "Nadia"), "Peanuts")
    table = ApplicationController.render(partial: "shared/people_table", locals: {
      rows: [ row ], link: nil, status: ->(_) { "Going" }, columns: [ [ "Allergies", ->(r) { r.allergy } ], [ '<span data-column-chooser-label>Notes</span> <button type="button">filter (2)</button>'.html_safe, ->(_) { "" } ] ],
      choose_columns: ("kit-people" unless wrapper)
    })
    html = ApplicationController.helpers.tag.div(before.html_safe + (table * tables).html_safe, id: "kit-table", data: wrapper)
    execute_script(<<~JS, html)
      document.querySelector("main").insertAdjacentHTML("afterbegin", arguments[0])
    JS
  end


  # A hand-written table with Name, Amount, Due and Team headings (or the
  # given headings) and a "Later" separator row, in a wrapper with the Columns
  # chooser (and so the table filter). rows: [name, amount, due, team]; after:
  # more such rows below the separator (a group listed apart); extra: true adds
  # a ticked box per row, a skip-marked column and one with no heading text;
  # foot: true adds a Total footer; form: true wraps it in a form with an
  # Order button; off: true marks the table's wrapper data-table-filter="off".
  # keys: { heading => data-column-key }, or an Array of keys by position;
  # before: HTML in the wrapper, ahead
  # of the tables.
  def add_filter_table(rows, tables: 1, extra: false, off: false, after: [], foot: false, form: false, headings: [ "Name", "Amount", "Due", "Team" ], keys: {}, before: "")
    helpers = ApplicationController.helpers
    headings += [ "Bring", "Notes", "" ] if extra
    key_for = ->(heading, index) { keys.is_a?(Array) ? keys[index] : keys[heading] }
    head = helpers.tag.thead(helpers.tag.tr(helpers.safe_join(headings.each_with_index.map { |heading, index| helpers.tag.th(heading, data: { table_filter_skip: (true if heading == "Notes"), column_key: key_for.call(heading, index) }) })))
    row_tags = ->(list) do
      helpers.safe_join(list.map do |row|
        cells = row.map { |cell| helpers.tag.td(cell) }
        cells += [ helpers.tag.td(helpers.check_box_tag("bring[]", row.first, true, id: nil)), helpers.tag.td("Soon"), helpers.tag.td("x") ] if extra
        helpers.tag.tr(helpers.safe_join(cells))
      end)
    end
    body = helpers.tag.tbody(row_tags.call(rows) + helpers.tag.tr(helpers.tag.td("Later", colspan: headings.size)) + row_tags.call(after))
    body += helpers.tag.tfoot(helpers.tag.tr(helpers.tag.td("Total") + helpers.tag.td("99", colspan: headings.size - 1))) if foot
    table = helpers.tag.div(helpers.tag.table(head + body, class: "table"), class: "table-responsive", data: (off ? { table_filter: "off" } : {}))
    content = (table * tables).html_safe
    content = helpers.tag.form(content + helpers.tag.button("Order", type: "submit", class: "btn btn-primary"), action: badge_types_path, method: "get") if form
    html = helpers.tag.div(before.html_safe + content, id: "kit-filter-table", data: helpers.column_chooser_data("kit-filter"))
    visit badge_types_path
    execute_script("localStorage.clear()")
    execute_script(<<~JS, html)
      document.querySelector("main").insertAdjacentHTML("afterbegin", arguments[0])
    JS
  end

  def current_query
    Rack::Utils.parse_nested_query(URI.parse(current_url).query)
  end

  def open_filter(name)
    find("[aria-label='Filter #{name}']", match: :first).click
  end

  # The first cell of each row shown, in order, across every table.
  def first_cells
    all("tbody tr", visible: true).map { |row| row.find("td", match: :first).text }
  end

  # Touch emulation: the page then matches (pointer: coarse).
  def emulate_touch(enabled = true)
    page.driver.browser.execute_cdp("Emulation.setTouchEmulationEnabled", enabled: enabled, maxTouchPoints: 1)
  end

  # Renders shared/_action_row and adds it to the current page, so the test
  # needs no screen of its own.
  def add_action_row(specs)
    actions = specs.map do |label, path, style, destructive|
      ScreenKit::Action.new(label:, path:, style:, destructive: destructive || false)
    end
    html = ApplicationController.render(partial: "shared/action_row", locals: { actions: actions })
    execute_script(<<~JS, html)
      const card = document.createElement("div")
      card.id = "kit-row"
      card.className = "card"
      card.innerHTML = arguments[0]
      document.querySelector("main").prepend(card)
    JS
  end

  # Renders shared/_filter_bar with a season select and adds it to the page.
  def add_filter_bar(**locals)
    fields = ApplicationController.helpers.select_tag(:season, ApplicationController.helpers.options_for_select([ "2026", "2025" ]))
    html = ApplicationController.render(partial: "shared/filter_bar", locals: { url: badge_types_path, status: nil, fields: fields, **locals })
    execute_script(<<~JS, html)
      const card = document.createElement("div")
      card.id = "kit-filter"
      card.innerHTML = arguments[0]
      document.querySelector("main").prepend(card)
    JS
  end

  def background_of(selector, text:)
    find(selector, text: text, exact_text: true)
    evaluate_script(<<~JS)
      getComputedStyle([...document.querySelectorAll(#{selector.to_json})].find((el) => el.textContent.trim() === #{text.to_json})).backgroundColor
    JS
  end

  # The background of a plain button of the given style on this page.
  def button_colour(style)
    evaluate_script(<<~JS)
      (() => {
        const button = document.createElement("button")
        button.className = "btn #{style}"
        document.body.append(button)
        const colour = getComputedStyle(button).backgroundColor
        button.remove()
        return colour
      })()
    JS
  end
end
