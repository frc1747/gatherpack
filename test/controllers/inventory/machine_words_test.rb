require "test_helper"
require "support/inventory_world"

# Machines under the group's own name, and turned off (inventory spec
# §3.15): the menu, the Machines page, the place form and the unit actions
# follow Inventory setup.
class Inventory::MachineWordsTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include InventoryWorld

  setup do
    host! "localhost"
    @world = build_inventory_world
    @world.robot.update!(name: "Rover")
    @motor = tracked_item!(@world, name: "Motor", units: 2)
    @unit, @other = @motor.item_units.order(:code).to_a
  end

  def named(**settings, &block)
    with_inventory(@world, inventory_machine_name: "Robot", inventory_machine_name_plural: "Robots", **settings, &block)
  end

  def turned_off(&block)
    with_inventory(@world, inventory_machines: "off", &block)
  end

  def visible_text
    Nokogiri::HTML(response.body).css("title, body").map(&:text).join(" ")
  end

  def menu_labels
    GatherPack::Features.all.find { |feature| feature.key == :inventory }.nav_items.map(&:label)
  end

  test "the menu, Machines page, place form and install refusal use the group's names" do
    named do
      assert_includes menu_labels, "Robots"
      assert_not menu_labels.any? { |label| label.match?(/machine/i) }

      sign_in @world.keeper.user
      get inventory_machines_path
      assert_response :success
      assert_select "title", /Robots/
      assert_select "h1", "Robots"
      assert_select ".nav-item a[href=?]", inventory_machines_path, text: /Robots/
      assert_no_match(/machine/i, visible_text)

      get new_inventory_location_path
      assert_select "select[name='location[kind]'] option[value=machine]", text: /\ARobot /
      assert_no_match(/machine/i, visible_text)

      error = assert_raises(Inventory::Refused) { @unit.install!(into: @world.bin1, by: @world.admin) }
      assert_equal "Install it on a robot, or use Move for a storage place", error.message
      post install_inventory_unit_path(@unit), params: {}
      assert_equal "Pick a robot, or type the code of the part to put it in", flash[:alert]
    end
  end

  test "the defaults still say Machine" do
    with_inventory(@world) do
      assert_includes menu_labels, "Machines"
      assert_equal "a machine", Inventory.machine_word(article: true)
      sign_in @world.member.user
      get inventory_machines_path
      assert_select "h1", "Machines"
    end
  end

  test "turned off: no menu item and no Machines page" do
    turned_off do
      assert_not_includes menu_labels, "Machines"

      sign_in @world.keeper.user
      get inventory_root_path
      assert_select "a[href=?]", inventory_machines_path, count: 0

      get inventory_machines_path
      assert_redirected_to inventory_root_path
      get inventory_machine_path(@world.robot)
      assert_redirected_to inventory_root_path
    end
  end

  test "turned off: a machine already made stays a place, with its parts listed and a way to take them off" do
    @other.install!(into: @world.robot, by: @world.admin)
    turned_off do
      sign_in @world.keeper.user
      get inventory_locations_path
      assert_select "a[href=?]", inventory_location_path(@world.robot), text: "Rover"
      assert_select ".badge", text: /machine/i, count: 0

      get inventory_location_path(@world.robot)
      assert_response :success
      assert_select "#units_here", /#{@other.identifier_name}/
      assert_no_match(/machine/i, visible_text)

      get inventory_unit_path(@other)
      assert_select "#unit_actions a", text: "Take off"
      assert_no_match(/machine/i, visible_text)
      post take_off_inventory_unit_path(@other), params: { location_id: @world.bin2.id }
      assert_equal @world.bin2, @other.reload.location

      error = assert_raises(Inventory::Refused) { @unit.install!(into: @world.robot, by: @world.admin) }
      assert_equal "Machines are turned off", error.message
    end
  end

  test "turned off: Install only puts a part inside another one" do
    turned_off do
      sign_in @world.keeper.user
      get inventory_unit_path(@unit)
      assert_select "#unit_actions a", text: "Install"
      get inventory_unit_action_form_path(@unit, act: "install")
      assert_response :success
      assert_select "select[name=location_id]", count: 0
      assert_select "label[for=unit_code]", "Inside another part: its code"
      assert_no_match(/machine/i, visible_text)

      post install_inventory_unit_path(@unit), params: { location_id: @world.robot.id }
      assert_equal "Machines are turned off", flash[:alert]
      assert_equal @world.bin1, @unit.reload.location
      post install_inventory_unit_path(@unit), params: {}
      assert_equal "Type the code of the part to put it in", flash[:alert]

      post install_inventory_unit_path(@unit), params: { unit_code: @other.code }
      assert_equal @other, @unit.reload.installed_in
      # The only other part is now inside it, so it has nothing to go into.
      assert_not ItemUnitPolicy.new(@world.keeper.user, @other).install?
    end
  end

  test "turned off: no Install when there's no other part to go into" do
    @other.retire!(by: @world.admin, note: "Worn out")
    turned_off do
      assert_not ItemUnitPolicy.new(@world.keeper.user, @unit).install?
      sign_in @world.keeper.user
      get inventory_unit_path(@unit)
      assert_select "#unit_actions a", text: "Install", count: 0
      assert_select "#unit_actions a", text: "Move"
      get inventory_unit_action_form_path(@unit, act: "install")
      assert_redirected_to root_path
      post install_inventory_unit_path(@unit), params: { location_id: @world.robot.id }
      assert_equal @world.bin1, @unit.reload.location
    end
  end

  test "turned off: a machine place can be edited into a storage place, and nothing becomes a machine" do
    turned_off do
      sign_in @world.keeper.user
      get new_inventory_location_path
      assert_select "select[name='location[kind]']", count: 0
      post inventory_locations_path, params: { location: { name: "Cart", team_id: @world.club.id, kind: "machine" } }
      assert_response :unprocessable_entity
      assert_not Location.exists?(name: "Cart")

      get edit_inventory_location_path(@world.bin1)
      assert_select "select[name='location[kind]']", count: 0

      get edit_inventory_location_path(@world.robot)
      assert_select "select[name='location[kind]'] option", count: 1
      assert_select "select[name='location[kind]'] option[value=storage]"
      assert_no_match(/machine/i, visible_text)
      patch inventory_location_path(@world.robot), params: { location: { name: "Rover", kind: "storage" } }
      assert_redirected_to inventory_location_path(@world.robot)
      assert @world.robot.reload.storage?
    end
  end

  test "the setup page shows and saves the machine settings" do
    with_inventory(@world) do
      sign_in @world.admin.user
      get inventory_setup_path
      assert_includes response.body, "Things Parts Get Installed On"
      assert_includes response.body, "What One Is Called"
      assert_includes response.body, "What Several Are Called"
      next if Settings.respond_to?(:input)

      patch inventory_setup_path, params: { settings: { inventory_machines: "off", inventory_machine_name: "Project",
        inventory_machine_name_plural: "" } }
      assert_not Inventory.machines?
      assert_equal "Projects", Inventory.machine_word(count: :many, capitalize: true)
    end
  end
end
