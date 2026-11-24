require "application_system_test_case"
require_relative "../support/forms_world"
require_relative "../support/settings_test_helper"

# On a form's results page the labels and totals follow the table's heading
# filters and sort, and Download CSV carries them.
class FormResultsFiltersSystemTest < ApplicationSystemTestCase
  include Devise::Test::IntegrationHelpers
  include FormsWorld

  setup do
    # config.hosts allows localhost, not Capybara's default 127.0.0.1.
    @always_include_port = Capybara.always_include_port
    Capybara.app_host = "http://localhost"
    Capybara.always_include_port = true
    @restore_settings = SettingsTestHelper.apply(feature_forms: "true")

    build_person_fields_world
    @form = create_world_form("Lunch", respond: "self_and_leaders")
    @sandwich = add_choice(@form, "Sandwich", [ "Slim 1", "Slim 4", "Big John" ])
    respond(@form, :a1, as: :a1, answers: { @sandwich.key => "Slim 4" })
    respond(@form, :a2, as: :a2, answers: { @sandwich.key => "Slim 4" })
    respond(@form, :b1, as: :b1, answers: { @sandwich.key => "Big John" })
    sign_in person(:pack_leader).user
  end

  teardown do
    @restore_settings&.call
    Capybara.app_host = nil
    Capybara.always_include_port = @always_include_port
  end

  test "labels and totals keep to the rows the heading filters leave, in the table's order" do
    visit form_path(@form)
    assert_equal({ "Slim 1" => "0", "Slim 4" => "2", "Big John" => "1" }, totals.slice("Slim 1", "Slim 4", "Big John"))
    assert_equal labels.size, labels(shown: true).size, "with no filter every label is there"

    within "#responses" do
      find("button[aria-label='Filter Sandwich']").click
      find("input[data-table-filter-tick='Sandwich'][value='Slim 4']").check
    end
    assert_selector "#responses tbody tr", count: 2, visible: true
    assert_equal({ "Slim 1" => "0", "Slim 4" => "2", "Big John" => "0" }, totals.slice("Slim 1", "Slim 4", "Big John"))
    assert_equal [ person(:a1), person(:a2) ].map(&:identifier_name), labels(shown: true)

    person_heading = find("#responses th", text: "Person", match: :first)
    2.times { person_heading.find("[data-table-filter-label]").click }
    assert_selector "#responses th[aria-sort=descending]"
    assert_equal [ person(:a2), person(:a1) ].map(&:identifier_name), labels(shown: true)

    find("a[data-table-filter-clear]", text: "Clear filters").click
    assert_equal "1", totals["Big John"]
    assert_includes labels(shown: true), person(:b1).identifier_name
  end

  test "Download CSV carries the heading filters and sort" do
    visit form_path(@form)
    within "#responses" do
      find("button[aria-label='Filter Sandwich']").click
      find("input[data-table-filter-tick='Sandwich'][value='Slim 4']").check
    end
    # Keep the click from downloading; the carry has already set the URL by then.
    link = find("a", text: "Download CSV")
    execute_script("arguments[0].addEventListener('click', (event) => event.preventDefault(), { once: true })", link)
    link.click
    query = Rack::Utils.parse_nested_query(URI(link[:href]).query)
    assert_equal({ @sandwich.id => "Slim 4" }, query["tf"])
  end

  private

  def totals
    all("#totals tr").to_h { |row| row.all("td").map(&:text) }
  end

  # Labels print only; read them whether or not they're on screen.
  def labels(shown: false)
    evaluate_script(<<~JS, shown)
      [ ...document.querySelectorAll("#labels [data-form-results-target=label]") ]
        .filter((label) => !arguments[0] || !label.hidden)
        .map((label) => label.querySelector(".fw-bold").textContent.trim())
    JS
  end
end
