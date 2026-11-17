require "test_helper"
require "support/inventory_world"

class Inventory::MachinesControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include InventoryWorld

  setup do
    host! "localhost"
    @world = build_inventory_world
    @motor = tracked_item!(@world, name: "Motor", units: 3)
    @module_item = tracked_item!(@world, name: "Module", units: 1)
    @module = @module_item.item_units.first
    @motor1, @motor2, @spare = @motor.item_units.order(:code).to_a
  end

  def as(person, &block)
    with_inventory(@world) do
      sign_in person.user
      block.call
    end
  end

  test "on the Machines page only Machines is highlighted, and /inventory still shows the stock page" do
    as(@world.keeper) do
      get inventory_machines_path
      assert_select ".sidebar a.active", count: 1
      assert_select ".sidebar a.active[href=?]", inventory_machines_path
      get inventory_stock_path
      assert_select ".sidebar a.active[href=?]", inventory_stock_path, count: 1
      assert_select ".sidebar a.active", count: 1
      get inventory_root_path
      assert_response :success
      assert_select "form[role=search]"
    end
  end

  test "turns requests away while the feature is off" do
    with_settings(feature_inventory: "false") do
      sign_in @world.member.user
      get inventory_machines_path
      assert_redirected_to root_path
    end
  end

  test "a member lists the machines they can see, with part counts" do
    @module.install!(into: @world.robot, by: @world.admin)
    other = Location.create!(team: @world.art, name: "Art robot", kind: "machine")
    as(@world.member) do
      get inventory_machines_path
      assert_response :success
      assert_select "#machines", /Robot/
      assert_select "#machines", /1 part/
      assert_select "#machines", text: /#{other.name}/, count: 0
    end
  end

  test "the machine page nests units by sub-assembly and puts flagged ones on top" do
    @motor1.install!(into: @module, by: @world.admin)
    @motor2.install!(into: @module, by: @world.admin)
    @module.install!(into: @world.robot, by: @world.admin)
    @motor2.mark_for_repair!(by: @world.admin, note: "Hot")
    as(@world.member) do
      get inventory_machine_path(@world.robot)
      assert_response :success
      assert_select "#flagged_units", /MOT-2/
      assert_select "#installed_units > li##{ActionView::RecordIdentifier.dom_id(@module)}" do
        assert_select "ul li", 2
        assert_select "ul li", /MOT-1/
      end
      assert_select "form#install_part"
    end
  end

  test "someone who can't see the machine gets not found" do
    as(@world.outsider) do
      get inventory_machine_path(@world.robot)
      assert_response :not_found
    end
  end

  test "a storage place isn't a machine" do
    as(@world.member) do
      get inventory_machine_path(@world.bin1)
      assert_response :not_found
    end
  end

  test "install a part by its code" do
    as(@world.member) do
      post install_inventory_machine_path(@world.robot), params: { code: " mot-3 " }
      assert_redirected_to inventory_machine_path(@world.robot)
      assert_equal @world.robot, @spare.reload.location
    end
  end

  test "an unknown code is refused" do
    as(@world.member) do
      post install_inventory_machine_path(@world.robot), params: { code: "NOPE" }
      assert_equal "No part has the code NOPE", flash[:alert]
    end
  end

  test "a part marked for repair goes to its install page to confirm" do
    @spare.mark_for_repair!(by: @world.admin, note: "Hot", condition: "broken")
    as(@world.member) do
      post install_inventory_machine_path(@world.robot), params: { code: "MOT-3" }
      assert_redirected_to inventory_unit_action_form_path(@spare, act: "install", location_id: @world.robot.id)
      assert_equal @world.bin1, @spare.reload.location

      follow_redirect!
      assert_select "#install_question", /marked Broken: install anyway\?/
      assert_select "select#location_id option[selected][value=?]", @world.robot.id
    end
  end

  test "a member whose unit actions leave out install is refused" do
    as(@world.member) do
      with_settings(inventory_member_unit_actions: "check") do
        Inventory::Current.reset
        post install_inventory_machine_path(@world.robot), params: { code: "MOT-3" }
        assert_equal "You can't install this unit", flash[:alert]
        assert_equal @world.bin1, @spare.reload.location
      end
    end
  end

  test "a code two teams use installs the machine's team's unit" do
    theirs = tracked_item!(@world, name: "Motor", team: @world.robotics, units: 1).item_units.first
    assert_equal "MOT-1", theirs.code
    as(@world.member) do
      post install_inventory_machine_path(@world.robot), params: { code: "MOT-1" }
      assert_redirected_to inventory_machine_path(@world.robot)
      assert_equal @world.robot, theirs.reload.location
      assert_equal @world.bin1, @motor1.reload.location
    end
  end

  test "a code that still matches more than one part is refused" do
    # The club's and build's MOT-1, on a robotics machine.
    tracked_item!(@world, name: "Motor", team: @world.build, units: 1)
    as(@world.builder) do
      post install_inventory_machine_path(@world.robot), params: { code: "MOT-1" }
      assert_equal "2 parts have the code MOT-1: scan the label of the one you mean", flash[:alert]
      assert_not ItemUnit.where(location: @world.robot).exists?
    end
  end

  test "a code matches before a serial number" do
    @spare.update!(serial_number: "MOT-1")
    as(@world.member) do
      post install_inventory_machine_path(@world.robot), params: { code: "MOT-1" }
      assert_equal @world.robot, @motor1.reload.location
      assert_equal @world.bin1, @spare.reload.location
    end
  end

  test "a scanned label URL installs its unit" do
    as(@world.member) do
      post install_inventory_machine_path(@world.robot), params: { code: inventory_unit_url(@spare, host: "localhost") }
      assert_redirected_to inventory_machine_path(@world.robot)
      assert_equal @world.robot, @spare.reload.location
    end
  end

  test "a scanned label for a part the viewer can't see is refused" do
    hidden = tracked_item!(@world, name: "Lamp", team: @world.art, units: 1).item_units.first
    as(@world.member) do
      post install_inventory_machine_path(@world.robot), params: { code: "https://example.org/inventory/units/#{hidden.to_param}" }
      assert_equal "That label isn't for a part you can see", flash[:alert]
      assert_equal @world.bin1, hidden.reload.location
    end
  end

  test "units inside a part the viewer can't see are still listed, and the count matches" do
    build_module = tracked_item!(@world, name: "Bracket", team: @world.build, units: 1).item_units.first
    @motor1.install!(into: build_module, by: @world.admin)
    build_module.install!(into: @world.robot, by: @world.admin)
    as(@world.member) do
      get inventory_machines_path
      assert_select "#machines", /1 part\b/

      get inventory_machine_path(@world.robot)
      assert_select "#installed_units > li", 1
      assert_select "#installed_units > li", /MOT-1.*inside another part/m
      assert_select "#installed_units", text: /BRA-1/, count: 0
    end
    as(@world.builder) do
      get inventory_machines_path
      assert_select "#machines", /2 parts/
      get inventory_machine_path(@world.robot)
      assert_select "#installed_units > li", 1
      assert_select "#installed_units > li li", /MOT-1/
    end
  end
end
