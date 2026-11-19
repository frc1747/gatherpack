require "application_system_test_case"

class PinnedFormButtonsTest < ApplicationSystemTestCase
  include Devise::Test::IntegrationHelpers

  PHONE = [ 390, 700 ].freeze
  DESKTOP = [ 1400, 700 ].freeze

  setup do
    # config.hosts allows localhost, not Capybara's default 127.0.0.1.
    @always_include_port = Capybara.always_include_port
    Capybara.app_host = "http://localhost"
    Capybara.always_include_port = true

    @path = Rails.root.join("tmp", "pinned-form-buttons-system-test-#{Process.pid}.pstore").to_s
    File.delete(@path) if File.exist?(@path)
    @original_store = Settings.instance.store
    Settings.instance.store = PStore.new(@path, true)

    @user = User.create!(email: "admin@example.com", password: "Password1!", admin: true)
    Person.create!(user: @user, first_name: "Ada", last_name: "Admin")
    sign_in @user
  end

  teardown do
    page.driver.browser.manage.window.resize_to(1400, 1400)
    Settings.instance.store = @original_store
    File.delete(@path) if File.exist?(@path)
    Capybara.app_host = nil
    Capybara.always_include_port = @always_include_port
  end

  [ [ "phone", PHONE ], [ "desktop", DESKTOP ] ].each do |name, size|
    test "the settings page's Save is in view at the top of the page at #{name} width" do
      Settings[:feature_pinned_form_buttons] = "true"
      page.driver.browser.manage.window.resize_to(*size)
      visit settings_path

      assert long_page?, "the settings page should run past the window"
      assert save_in_view?, "Save should be pinned to the bottom of the window"
    end

    test "the settings page's Save stays at the end of the form at #{name} width when the feature is off" do
      page.driver.browser.manage.window.resize_to(*size)
      visit settings_path

      assert long_page?, "the settings page should run past the window"
      assert_not save_in_view?, "Save should be at the end of the form, below the window"
    end
  end

  test "a short form's buttons stay where they are" do
    Settings[:feature_pinned_form_buttons] = "true"
    page.driver.browser.manage.window.resize_to(1400, 1400)
    visit new_badge_type_path

    # The row sits right under the fields it follows, with the window to spare.
    footer_top, footer_bottom, fields_bottom = evaluate_script(<<~JS)
      (() => {
        const footer = document.querySelector("main form .card-footer")
        const rect = footer.getBoundingClientRect()
        return [rect.top, rect.bottom, footer.previousElementSibling.getBoundingClientRect().bottom]
      })()
    JS
    assert_in_delta fields_bottom, footer_top, 1
    assert_operator footer_bottom, :<, evaluate_script("window.innerHeight")
    assert_not edge_shown?("main form .card-footer"), "a row that isn't stuck has no edge"
  end

  test "a stuck row shows its edge only while it's stuck" do
    Settings[:feature_pinned_form_buttons] = "true"
    page.driver.browser.manage.window.resize_to(*DESKTOP)
    visit settings_path
    save_card = "main form > .card:has(> .card-footer:only-child)"

    assert edge_shown?(save_card), "the stuck Save row should have a top border and shadow"

    execute_script("window.scrollTo({ top: document.documentElement.scrollHeight, behavior: \"instant\" })")
    assert_not edge_shown?(save_card), "at the end of the form the row settles back without its edge"
  end

  [ [ "gp-form-actions", "gp-form-actions" ], [ "d-flex gap-2", "d-flex gap-2" ] ].each do |name, row_class|
    test "a #{name} row ending a long form is pinned" do
      Settings[:feature_pinned_form_buttons] = "true"
      page.driver.browser.manage.window.resize_to(*DESKTOP)
      visit new_badge_type_path
      add_long_form(row_class:, method: "post")

      assert save_in_view?("#long-form"), "the #{name} row should be pinned to the bottom of the window"
    end
  end

  test "a long search form's button row isn't pinned" do
    Settings[:feature_pinned_form_buttons] = "true"
    page.driver.browser.manage.window.resize_to(*DESKTOP)
    visit new_badge_type_path
    add_long_form(row_class: "d-flex gap-2", method: "get")

    assert_not save_in_view?("#long-form"), "a GET form's row should stay at the end of the form"
  end

  private

  def long_page?
    evaluate_script("document.documentElement.scrollHeight > window.innerHeight + 200")
  end

  # A long form of plain fields ending in a button row, added to the page so
  # the test needs no screen of its own.
  def add_long_form(row_class:, method:)
    execute_script(<<~JS, row_class, method)
      const [rowClass, method] = arguments
      const form = document.createElement("form")
      form.id = "long-form"
      form.method = method
      for (let i = 0; i < 40; i++) {
        form.insertAdjacentHTML("beforeend", `<div class="mb-3"><input class="form-control" name="field${i}"></div>`)
      }
      form.insertAdjacentHTML("beforeend", `<div class="${rowClass}"><input type="submit" class="btn btn-primary" value="Save"></div>`)
      document.querySelector("main").prepend(form)
      window.scrollTo({ top: 0, behavior: "instant" })
    JS
  end

  # Whether the row's ::before edge (top border and shadow) is drawn, after
  # the browser has had two frames to update scroll-state queries.
  def edge_shown?(selector)
    evaluate_async_script(<<~JS, selector)
      const [selector, done] = arguments
      requestAnimationFrame(() => requestAnimationFrame(() => {
        const style = getComputedStyle(document.querySelector(selector), "::before")
        done(style.content !== "none" && style.boxShadow !== "none")
      }))
    JS
  end

  def save_in_view?(form = "main form")
    evaluate_script(<<~JS)
      (() => {
        const rect = document.querySelector("#{form} input[type=submit][value=Save]").getBoundingClientRect()
        return window.scrollY === 0 && rect.top >= 0 && rect.bottom <= window.innerHeight
      })()
    JS
  end
end
