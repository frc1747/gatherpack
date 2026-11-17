require "test_helper"
require "support/inventory_world"

# Place types that parts get installed on (inventory spec §3.15), named and
# retired on the place types list: the menu, their pages, the place form and
# the unit actions follow the list. Retiring the Machine type is what
# turning machines off used to be.
class Inventory::PlaceTypesTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include InventoryWorld

  setup do
    host! "localhost"
    @world = build_inventory_world
    @world.robot.update!(name: "Rover")
    @machine = location_type("machine")
    @motor = tracked_item!(@world, name: "Motor", units: 2)
    @unit, @other = @motor.item_units.order(:code).to_a
  end

  def visible_text
    Nokogiri::HTML(response.body).css("title, body").map(&:text).join(" ")
  end

  def menu_labels
    GatherPack::Features.all.find { |feature| feature.key == :inventory }.nav_items.map(&:label)
  end

  test "a renamed type names the menu, its page, the place form and the install refusals" do
    @machine.update!(name: "Robot", plural: "Robots")
    with_inventory(@world) do
      assert_includes menu_labels, "Robots"
      assert_not menu_labels.any? { |label| label.match?(/machine/i) }

      sign_in @world.keeper.user
      get inventory_machines_path
      assert_redirected_to inventory_machine_type_path(@machine)
      follow_redirect!
      assert_select "title", /Robots/
      assert_select "h1", "Robots"
      assert_select ".nav-item a[href=?]", inventory_machine_type_path(@machine), text: /Robots/
      assert_no_match(/machine/i, visible_text)

      get new_inventory_location_path
      assert_select "select[name='location[location_type_id]'] option[value=?]", @machine.id, text: "Robot"
      assert_select "select[name='location[location_type_id]'] option[selected]", text: "Storage"
      assert_no_match(/machine/i, visible_text)

      error = assert_raises(Inventory::Refused) { @unit.install!(into: @world.bin1, by: @world.admin) }
      assert_equal "Install it on a robot, or use Move for a storage place", error.message
      post install_inventory_unit_path(@unit), params: {}
      assert_equal "Pick a robot, or type the code of the part to put it in", flash[:alert]
    end
  end

  test "two types parts go on get a menu entry and a page each" do
    base = LocationType.create!(name: "Practice base", holds_stock: false, holds_installed_parts: true)
    practice = Location.create!(team: @world.robotics, name: "Field base", location_type: base)
    with_inventory(@world) do
      assert_equal [ "Stock", "Machines", "Practice bases" ], menu_labels.first(3)
      sign_in @world.member.user
      get inventory_machine_type_path(base)
      assert_select "h1", "Practice bases"
      assert_select "#machines", text: /Field base/
      assert_select "#machines", text: /Rover/, count: 0
      get inventory_machine_type_path(@machine)
      assert_select "#machines", text: /Field base/, count: 0

      @unit.install!(into: practice, by: @world.admin)
      assert_equal practice, @unit.reload.location
      get inventory_machine_path(practice)
      assert_response :success
      assert_select ".breadcrumb a[href=?]", inventory_machine_type_path(base), text: "Practice bases"
    end
  end

  test "retired: no menu item and no page" do
    @machine.retire!
    with_inventory(@world) do
      assert_not_includes menu_labels, "Machines"

      sign_in @world.keeper.user
      get inventory_root_path
      assert_select "a[href=?]", inventory_machine_type_path(@machine), count: 0

      get inventory_machines_path
      assert_redirected_to inventory_root_path
      get inventory_machine_path(@world.robot)
      assert_redirected_to inventory_location_path(@world.robot)
    end
  end

  test "retired: a place of that type stays one, with its parts listed and a way to take them off" do
    @other.install!(into: @world.robot, by: @world.admin)
    @machine.retire!
    with_inventory(@world) do
      sign_in @world.keeper.user
      get inventory_locations_path
      assert_select "a[href=?]", inventory_location_path(@world.robot), text: "Rover"
      assert_select ".badge", text: /machine/i, count: 0

      get inventory_location_path(@world.robot)
      assert_response :success
      assert_select "#units_here", /#{@other.identifier_name}/

      get inventory_unit_path(@other)
      assert_select "#unit_actions a", text: "Take off"
      post take_off_inventory_unit_path(@other), params: { location_id: @world.bin2.id }
      assert_equal @world.bin2, @other.reload.location
      assert_equal @machine, @world.robot.reload.location_type

      error = assert_raises(Inventory::Refused) { @unit.install!(into: @world.robot, by: @world.admin) }
      assert_equal "Machines are retired", error.message
    end
  end

  test "retired: Install only puts a part inside another one" do
    @machine.retire!
    with_inventory(@world) do
      sign_in @world.keeper.user
      get inventory_unit_path(@unit)
      assert_select "#unit_actions a", text: "Install"
      get inventory_unit_action_form_path(@unit, act: "install")
      assert_response :success
      assert_select "select[name=location_id]", count: 0
      assert_select "label[for=unit_code]", "Inside another part: its code"
      assert_no_match(/machine/i, visible_text)

      post install_inventory_unit_path(@unit), params: { location_id: @world.robot.id }
      assert_equal "Machines are retired", flash[:alert]
      assert_equal @world.bin1, @unit.reload.location
      post install_inventory_unit_path(@unit), params: {}
      assert_equal "Type the code of the part to put it in", flash[:alert]

      post install_inventory_unit_path(@unit), params: { unit_code: @other.code }
      assert_equal @other, @unit.reload.installed_in
      assert_not ItemUnitPolicy.new(@world.keeper.user, @other).install?
    end
  end

  test "retired: no Install when there's no other part to go into" do
    @other.retire!(by: @world.admin, note: "Worn out")
    @machine.retire!
    with_inventory(@world) do
      assert_not ItemUnitPolicy.new(@world.keeper.user, @unit).install?
      sign_in @world.keeper.user
      get inventory_unit_path(@unit)
      assert_select "#unit_actions a", text: "Install", count: 0
      assert_select "#unit_actions a", text: "Move"
    end
  end

  test "retired: the place form doesn't offer it, a place of that type shows it as retired and can change to Storage" do
    @machine.retire!
    with_inventory(@world) do
      sign_in @world.keeper.user
      get new_inventory_location_path
      assert_select "select[name='location[location_type_id]'] option[value=?]", @machine.id, count: 0
      post inventory_locations_path, params: { location: { name: "Cart", team_id: @world.club.id, location_type_id: @machine.id } }
      assert_response :unprocessable_entity
      assert_not Location.exists?(name: "Cart")

      get edit_inventory_location_path(@world.robot)
      assert_select "select[name='location[location_type_id]'] option[selected]", text: "Machine (retired)"
      patch inventory_location_path(@world.robot), params: { location: { name: "Rover", location_type_id: location_type("storage").id } }
      assert_redirected_to inventory_location_path(@world.robot)
      assert @world.robot.reload.storage?
    end
  end

  test "the item form picks a stock unit from the list, and a retired one stays on its item" do
    box = stock_unit("box")
    @world.screws.update!(stock_unit: box)
    box.retire!
    with_inventory(@world) do
      sign_in @world.keeper.user
      get new_inventory_item_path
      assert_select "select[name='item[stock_unit_id]'] option[selected]", text: "each"
      assert_select "select[name='item[stock_unit_id]'] option", text: "box", count: 0
      get edit_inventory_item_path(@world.screws)
      assert_select "select[name='item[stock_unit_id]'] option[selected]", text: "box (retired)"
    end
  end

  test "the condition choices on unit pages come from the list and its flags" do
    UnitCondition.create!(name: "Scratched", needs_attention: true)
    unit_condition("worn").retire!
    with_inventory(@world) do
      sign_in @world.keeper.user
      get inventory_unit_action_form_path(@unit, act: "mark_for_repair")
      assert_select "input[name=condition]", 3
      assert_select "label", text: "Scratched"
      get inventory_unit_action_form_path(@unit, act: "check")
      assert_select "label", text: "Worn", count: 0
      assert_select "label", text: "Retired", count: 0
      assert_select "input[name=condition][checked][value=?]", unit_condition("new").id
      get inventory_unit_action_form_path(@unit, act: "repaired")
      assert_select "label", text: "Good"
      assert_select "label", text: "Needs repair", count: 0
    end
  end
end
