require "application_system_test_case"
require_relative "../support/checklists_world"

class FamilyPageSystemTest < ApplicationSystemTestCase
  include Devise::Test::IntegrationHelpers
  include ChecklistsWorld

  # config.hosts allows localhost in test, but not Capybara's 127.0.0.1.
  setup do
    @saved_app_host = Capybara.app_host
    @saved_include_port = Capybara.always_include_port
    Capybara.app_host = "http://localhost"
    Capybara.always_include_port = true
    @restore_settings = SettingsTestHelper.apply(feature_my_gatherpack: "true", feature_forms: "true", feature_events: "true")
    page.driver.browser.manage.window.resize_to(390, 844)
    build_checklists_world
    @form = Form.create!(title: "A Very Long Consent Form Title For Everyone On The Team This Season", team: @members,
      respond_permission: "family", read_permission: "family", status: :draft)
    @form.form_audience_rules.create!(effect: :include, target_type: :team, team: @members, include_managers: true)
    @form.form_audience_rules.reset
    @form.update!(status: :open)
    Event.create!(name: "Practice", location: "North Field", start_time: 2.days.from_now, end_time: 2.days.from_now + 2.hours,
      event_type: event_types(:one), team: @members)
    sign_in person(:parent).user
  end

  teardown do
    # The browser is shared with other system tests.
    page.driver.browser.manage.window.resize_to(1400, 1400)
    @restore_settings&.call
    Capybara.app_host = @saved_app_host
    Capybara.always_include_port = @saved_include_port
  end

  # The page's styles load before application.css on a direct load and after
  # it on a Turbo visit.
  test "at 390 px the page is laid out the same on a direct load and a Turbo visit" do
    visit family_path
    assert_selector "[data-family-status]"
    direct = family_layout

    visit root_path
    assert_no_selector "[data-family-status]"
    page.execute_script("Turbo.visit(#{family_path.to_json})")
    assert_selector "[data-family-status]"

    assert_equal direct, family_layout
    assert_operator direct.fetch("pageWidth"), :<=, 390
    assert_operator direct.fetch("actionHeight"), :>=, 44
  end

  test "at 390 px the page fits and a form opens from its row" do
    visit family_path

    assert_selector "[data-family-status]", text: "1 thing needs you"
    assert_text "North Field"
    assert_operator page.evaluate_script("document.documentElement.scrollWidth"), :<=, 390

    within("[data-family-row=forms]") { click_link "Fill out" }

    assert_current_path edit_form_response_path(@form, person(:kid))
  end

  private

  def family_layout
    page.evaluate_script(<<~JS)
      (() => {
        const action = document.querySelector("[data-family-row=forms] .mg-row-action");
        const style = getComputedStyle(action);
        return { pageWidth: document.documentElement.scrollWidth, actionHeight: action.getBoundingClientRect().height, actionDisplay: style.display, actionAlign: style.alignItems };
      })()
    JS
  end
end
