require "application_system_test_case"
require "support/inventory_world"

# Tracked units on a phone (inventory spec §7, "Tracked units (system
# tests, phone-sized)").
class InventoryUnitsTest < ApplicationSystemTestCase
  include Devise::Test::IntegrationHelpers
  include InventoryWorld

  # config.hosts allows localhost in test, but not Capybara's 127.0.0.1.
  setup do
    @saved_app_host = Capybara.app_host
    @saved_include_port = Capybara.always_include_port
    Capybara.app_host = "http://localhost"
    Capybara.always_include_port = true
    page.driver.browser.manage.window.resize_to(390, 844)

    @world = build_inventory_world
    @restore_settings = SettingsTestHelper.apply(inventory_settings(@world))
    Inventory::Current.reset
    @battery = tracked_item!(@world, name: "Battery", units: 1, readings: [ { "name" => "Internal resistance", "unit" => "mΩ" } ])
    @motor = tracked_item!(@world, name: "Motor", units: 2)
    @module_item = tracked_item!(@world, name: "Module", units: 1)
    sign_in @world.member.user
  end

  teardown do
    # The browser is shared with other system tests.
    page.driver.browser.manage.window.resize_to(1400, 1400)
    @restore_settings&.call
    Inventory::Current.reset
    Capybara.app_host = @saved_app_host
    Capybara.always_include_port = @saved_include_port
  end

  def assert_no_sideways_scroll
    assert page.evaluate_script("document.documentElement.scrollWidth <= document.documentElement.clientWidth")
  end

  test "open a unit from its label link, take it off a machine into a bin, and check it with a reading" do
    unit = @battery.item_units.first
    unit.install!(into: @world.robot, by: @world.admin)
    label = Nokogiri::HTML(ApplicationController.render(partial: "inventory/labels/unit", locals: { unit: unit }))
    link = label.at_css("a")
    assert_equal "BAT-1", link.text

    visit URI(link["href"]).path
    assert_selector "h1", text: "BAT-1"
    assert_selector "#unit_whereabouts", text: "Robot"
    assert_no_sideways_scroll
    assert page.evaluate_script("document.querySelector('#unit_actions a').getBoundingClientRect().height >= 44")

    click_on "Take off"
    select "Shop › Cabinet › Bin 2", from: "Put it in"
    click_on "Take off"
    assert_text "Taken off, now in Bin 2"
    assert_selector "#unit_whereabouts", text: "Shop › Cabinet › Bin 2"

    click_on "Check"
    find("label", text: "Worn").click
    fill_in "Internal resistance (mΩ)", with: "21.5"
    click_on "Save check"
    assert_text "Check saved"
    assert_selector "h1 .badge", text: "Worn"
    within("#latest_readings") { assert_text "21.5" }
    within("#readings_history") { assert_text "21.5" }
    assert_equal @world.bin2, unit.reload.location
  end

  test "install a module with motors on a machine and see the machine page list all three" do
    motor1, motor2 = @motor.item_units.order(:code).to_a
    the_module = @module_item.item_units.first
    [ motor1, motor2 ].each do |motor|
      visit inventory_unit_path(motor)
      click_on "Install"
      fill_in "Or inside another part: its code", with: "MOD-1"
      click_on "Install"
      assert_text "Installed on MOD-1"
    end

    visit inventory_machine_path(@world.robot)
    assert_text "Nothing installed yet."
    fill_in "Install a part: scan its label or type its code", with: "mod-1"
    click_on "Install"
    assert_text "MOD-1 installed"

    within("#installed_units") do
      assert_selector "li", text: "MOD-1"
      assert_selector "li li", text: "MOT-1"
      assert_selector "li li", text: "MOT-2"
    end
    assert_no_sideways_scroll
    assert_equal [ @world.robot ] * 3, [ the_module, motor1, motor2 ].map { |unit| unit.reload.location }
  end

  test "installing a unit that needs repair asks first" do
    unit = @motor.item_units.order(:code).first
    unit.mark_for_repair!(by: @world.admin, note: "Grinding noise")
    visit inventory_machine_path(@world.robot)
    fill_in "Install a part: scan its label or type its code", with: "MOT-1"
    click_on "Install"

    assert_selector "#install_question", text: "This unit is marked Needs repair: install anyway?"
    click_on "Install anyway"
    assert_text "Installed on Robot"

    visit inventory_machine_path(@world.robot)
    within("#flagged_units") { assert_text "MOT-1" }
    assert unit.reload.events.last.confirmed?
  end
end
