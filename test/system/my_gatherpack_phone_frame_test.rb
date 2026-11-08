require "application_system_test_case"
require "my_gatherpack_test_helper"

class MyGatherpackPhoneFrameSystemTest < ApplicationSystemTestCase
  include Devise::Test::IntegrationHelpers
  include MyGatherpackTestHelper

  # config.hosts allows localhost in test, but not Capybara's 127.0.0.1.
  setup do
    @saved_app_host = Capybara.app_host
    @saved_include_port = Capybara.always_include_port
    Capybara.app_host = "http://localhost"
    Capybara.always_include_port = true
    turn_on_my_gatherpack
    Settings[:feature_time_tracking] = "true"
    page.driver.browser.manage.window.resize_to(390, 844)
    sign_in create_login("Morgan")
  end

  teardown do
    restore_my_gatherpack
    Capybara.app_host = @saved_app_host
    Capybara.always_include_port = @saved_include_port
  end

  test "at 390 px the header, tab bar and padding make a phone frame" do
    visit root_path

    assert_selector "header.navbar", text: "Northwind Community"
    assert_selector ".phone-tabs"
    assert_no_selector ".breadcrumb-container"
    assert_no_selector ".sidebar", visible: true, text: "Sign Out"

    tabs = all(".phone-tab").map { |tab| tab.text }
    assert_equal [ "Home", "Hours", "More" ], tabs
    assert page.evaluate_script("[...document.querySelectorAll('.phone-tab')].every(t => t.getBoundingClientRect().height >= 44)")

    bar = page.evaluate_script("document.querySelector('.phone-tabs').getBoundingClientRect().bottom")
    assert_equal page.evaluate_script("document.documentElement.clientHeight"), bar.round
    assert_operator page.evaluate_script("parseFloat(getComputedStyle(document.body).paddingBottom)"), :>=, 56
  end

  test "a long site title keeps the header to one line" do
    Settings[:title] = "The Northwind Community Association of Harrison County"
    visit root_path

    assert_operator page.evaluate_script("document.querySelector('header.navbar').getBoundingClientRect().height"), :<=, 72
  end

  test "header and sidebar targets are at least 44 px" do
    visit root_path
    assert page.evaluate_script("[...document.querySelectorAll('header.navbar .navbar-brand, header.navbar .navbar-toggler')].every(t => t.getBoundingClientRect().height >= 44)")

    find(".phone-tab", text: "More").click
    assert_selector "#sidebarMenu.show"
    sleep 0.5
    assert page.evaluate_script("[...document.querySelectorAll('#sidebarMenu .nav-item > a, #sidebarMenu summary')].filter(t => t.offsetParent).every(t => t.getBoundingClientRect().height >= 44)")
  end

  test "More opens the sidebar" do
    visit root_path
    find(".phone-tab", text: "More").click

    assert_selector "#sidebarMenu.show", text: "Sign Out"
  end

  test "at desktop width there is no tab bar" do
    page.driver.browser.manage.window.resize_to(1400, 900)
    visit root_path

    assert_no_selector ".phone-tabs"
  end
end
