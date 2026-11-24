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
    assert_selector "#kit-table .dropdown", count: 1
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
