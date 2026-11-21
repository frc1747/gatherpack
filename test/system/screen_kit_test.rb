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

  private

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
