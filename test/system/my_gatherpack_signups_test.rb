require "application_system_test_case"
require "my_gatherpack_test_helper"
require_relative "../support/signups_world"

class MyGatherpackSignupsSystemTest < ApplicationSystemTestCase
  include Devise::Test::IntegrationHelpers
  include MyGatherpackTestHelper
  include SignupsWorld

  # config.hosts allows localhost in test, but not Capybara's 127.0.0.1.
  setup do
    @saved_app_host = Capybara.app_host
    @saved_include_port = Capybara.always_include_port
    Capybara.app_host = "http://localhost"
    Capybara.always_include_port = true
    travel_to Time.zone.parse("2026-10-20 09:00")
    turn_on_my_gatherpack
    # SignupsWorld set this in a store turn_on_my_gatherpack replaced.
    Settings[:feature_signups] = "true"
    build_signups_world
  end

  teardown do
    restore_my_gatherpack
    Capybara.app_host = @saved_app_host
    Capybara.always_include_port = @saved_include_port
  end

  test "a sign-up is listed under Coming up and opens its sheet" do
    sheet = create_world_sheet
    create_world_signup(sheet.signup_positions.create!(name: "Cashier", capacity: 2), :worker)
    sign_in person(:worker).user

    visit root_path
    within("[data-home-column=coming_up]") { click_link "Cashier" }

    assert_current_path signup_sheet_path(sheet)
  end

  test "at 390 px a shift is claimed from the sheet through to saved data" do
    sheet = create_world_sheet
    position = sheet.signup_positions.create!(name: "Cashier", capacity: 2)
    sign_in person(:worker).user
    page.driver.browser.manage.window.resize_to(390, 844)

    visit signup_sheet_path(sheet)

    assert_selector ".mg-places-left", text: "Cashier: 2 places left"
    assert_no_sideways_scroll
    assert_full_width_sign_up_button

    click_link "Sign up"
    click_button "Sign up"

    assert_text "Your places"
    assert Signup.find_by!(person: person(:worker), signup_slot: slot_for(position)).active?
    assert_selector ".mg-places-left", text: "Cashier: 1 place left"
    assert_no_sideways_scroll
  ensure
    page.driver.browser.manage.window.resize_to(1400, 1400)
  end

  test "the Sign up button is full width after a direct load and after a Turbo visit" do
    sheet = create_world_sheet
    sheet.signup_positions.create!(name: "Cashier", capacity: 2)
    sign_in person(:worker).user
    page.driver.browser.manage.window.resize_to(390, 844)

    visit signup_sheets_path
    click_link sheet.title
    assert_selector ".mg-places-left"
    assert_full_width_sign_up_button

    visit signup_sheet_path(sheet)
    assert_full_width_sign_up_button
  ensure
    page.driver.browser.manage.window.resize_to(1400, 1400)
  end

  test "at 390 px Change, Cancel and the form buttons are at least 44 px tall" do
    sheet = create_world_sheet
    sheet.signup_positions.create!(name: "Cashier", capacity: 2)
    sign_in person(:worker).user
    page.driver.browser.manage.window.resize_to(390, 844)

    visit signup_sheet_path(sheet)
    click_link "Sign up"
    assert_buttons_tall "form .card-footer .btn"
    click_button "Sign up"

    assert_text "Your places"
    assert_buttons_tall "#my_signups .btn"
  ensure
    page.driver.browser.manage.window.resize_to(1400, 1400)
  end

  test "at 390 px a guardian picks a child under who is taking the place" do
    sheet = create_world_sheet(others_relationship_type_ids: [ @parent_of.id ])
    position = sheet.signup_positions.create!(name: "Cashier", capacity: 2)
    sign_in person(:parent).user
    page.driver.browser.manage.window.resize_to(390, 844)

    visit signup_sheet_path(sheet)
    click_link "Sign up"
    find("input[name='signup[person_id]'][value='#{person(:student).id}']").click
    click_button "Sign up"

    assert_text "Places you signed others up for"
    signup = Signup.find_by!(signup_slot: slot_for(position))
    assert_equal [ person(:student), person(:parent) ], [ signup.person, signup.signed_up_by ]
    assert_no_sideways_scroll
  ensure
    page.driver.browser.manage.window.resize_to(1400, 1400)
  end

  test "at 390 px a member on an anyone sheet picks who it is for from the name picker" do
    sheet = create_world_sheet(on_behalf_of_mode: :anyone)
    position = sheet.signup_positions.create!(name: "Cashier", capacity: 2)
    sign_in person(:student).user
    page.driver.browser.manage.window.resize_to(390, 844)

    visit signup_sheet_path(sheet)
    click_link "Sign up"
    find("#on_behalf_of_picker input[role=combobox]").fill_in(with: "Two")
    find("[role=option]", text: "StudentTwo World").click
    click_button "Sign up"

    assert_text "Your places"
    assert_equal person(:student2), Signup.find_by!(signup_slot: slot_for(position)).on_behalf_of
    assert_no_sideways_scroll
  ensure
    page.driver.browser.manage.window.resize_to(1400, 1400)
  end

  test "at 390 px with the flag off the same shift can still be claimed" do
    sheet = create_world_sheet
    position = sheet.signup_positions.create!(name: "Cashier", capacity: 2)
    Settings[:feature_my_gatherpack] = "false"
    sign_in person(:worker).user
    page.driver.browser.manage.window.resize_to(390, 844)

    visit signup_sheet_path(sheet)

    assert_no_selector ".mg-places-left"
    click_link "Sign up"
    click_button "Sign up"

    assert_text "Your places"
    assert Signup.exists?(person: person(:worker), signup_slot: slot_for(position))
  ensure
    page.driver.browser.manage.window.resize_to(1400, 1400)
  end

  test "at 390 px a parent can sign up on behalf of a child" do
    sheet = create_world_sheet(others_relationship_type_ids: [ @parent_of.id ], on_behalf_of_mode: :related_people)
    position = sheet.signup_positions.create!(name: "Cashier", capacity: 2)
    Membership.create!(person: person(:parent), team: @students)
    sign_in person(:parent).user
    page.driver.browser.manage.window.resize_to(390, 844)

    visit signup_sheet_path(sheet)
    click_link "Sign up"
    find("input[name='signup[on_behalf_of_id]'][value='#{person(:student).id}']").click
    click_button "Sign up"

    assert_text "Your places"
    assert Signup.exists?(person: person(:parent), on_behalf_of: person(:student), signup_slot: slot_for(position))
    assert_no_sideways_scroll
  ensure
    page.driver.browser.manage.window.resize_to(1400, 1400)
  end

  test "at desktop width the sheet keeps the longer count" do
    sheet = create_world_sheet
    sheet.signup_positions.create!(name: "Cashier", capacity: 2)
    sign_in person(:worker).user
    page.driver.browser.manage.window.resize_to(1400, 900)

    visit signup_sheet_path(sheet)

    assert_text "0 of 2 filled"
    assert_no_selector ".mg-places-left"
  end

  private

  def assert_full_width_sign_up_button
    box = page.evaluate_script("(b => { const r = b.getBoundingClientRect(); const row = b.closest('.mg-slot').getBoundingClientRect(); return { w: r.width, h: r.height, row: row.width, display: getComputedStyle(b).display, font: getComputedStyle(b).fontSize } })(document.querySelector('.mg-slot .btn-primary'))")
    assert_operator box["h"], :>=, 44
    assert_operator box["w"], :>=, box["row"] - 40
    assert_equal "block", box["display"]
    assert_equal "16px", box["font"]
  end

  def assert_buttons_tall(selector)
    assert page.evaluate_script("[...document.querySelectorAll('#{selector}')].every(b => b.getBoundingClientRect().height >= 44)")
  end

  def assert_no_sideways_scroll
    assert page.evaluate_script("document.documentElement.scrollWidth <= document.documentElement.clientWidth")
  end
end
