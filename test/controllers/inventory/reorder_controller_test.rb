require "test_helper"
require "support/inventory_world"

class Inventory::ReorderControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include InventoryWorld

  setup do
    host! "localhost"
    @world = build_inventory_world
    stock!(@world, 4)
    @world.screws.item_sources.create!(vendor_name: "Parts Depot", vendor_part_number: "PD-4", url: "https://example.com/pd-4")
    @wire = Item.create!(team: @world.club, name: "Red wire", reorder_point: 2, reorder_quantity: 3)
  end

  test "managers see low items grouped by vendor, No source yet first" do
    with_inventory(@world) do
      sign_in @world.keeper.user
      get inventory_reorder_path
      assert_response :success
      assert_equal [ "No source yet", "Parts Depot" ], css_select("h2").map { |h| h.text.strip }
      assert_select "input[name=?][value='16']", "quantities[#{@world.screws.id}]"
      assert_select "#reorder-actions button", text: "Print"
      assert_select "#reorder-actions button", text: "Download CSV"
    end
  end

  test "members can't open it" do
    with_inventory(@world) do
      sign_in @world.member.user
      get inventory_reorder_path
      assert_redirected_to root_path
    end
  end

  test "an action receives the ticked rows with the quantities shown" do
    with_inventory(@world) do
      sign_in @world.keeper.user
      get inventory_reorder_path(run: "csv", ticked: [ @world.screws.id ], quantities: { @world.screws.id => "20", @wire.id => "3" })
      assert_redirected_to inventory_reorder_path(format: :csv, items: { @world.screws.id => 20 })
    end
  end

  test "nothing ticked asks for a tick" do
    with_inventory(@world) do
      sign_in @world.keeper.user
      get inventory_reorder_path(run: "print")
      assert_redirected_to inventory_reorder_path
      assert_equal "Tick the items first.", flash[:alert]
    end
  end

  test "Download CSV lists the chosen items" do
    with_inventory(@world) do
      sign_in @world.keeper.user
      get inventory_reorder_path(format: :csv, items: { @world.screws.id => 20 })
      rows = CSV.parse(response.body, headers: true)
      assert_equal 1, rows.size
      assert_equal [ "M4 screw", "M4-12", "Parts Depot", "PD-4", "https://example.com/pd-4", "20" ],
        rows.first.fields.values_at(0, 2, 3, 4, 5, 6)
    end
  end

  test "Print shows the chosen items" do
    with_inventory(@world) do
      sign_in @world.keeper.user
      get inventory_reorder_path(print: 1, items: { @wire.id => 7 })
      assert_response :success
      assert_select "table", text: /Red wire/
      assert_select "table", text: /M4 screw/, count: 0
    end
  end

  test "a registered action appears and runs from the list's POST" do
    with_inventory(@world) do
      Inventory.extensions.register_reorder_action(:stub, label: "Do the thing", path: ->(rows) { "/inventory?q=#{rows.size}" })
      sign_in @world.keeper.user
      get inventory_reorder_path
      assert_select "form#reorder-form[method=post]"
      assert_select "#reorder-actions button", text: "Do the thing"
      post inventory_reorder_path, params: { run: "stub", ticked: [ @world.screws.id, @wire.id ] }
      assert_redirected_to "/inventory?q=2"
    ensure
      Inventory.extensions.instance_variable_get(:@reorder_actions).delete(:stub)
    end
  end

  test "a GET doesn't run an action that isn't declared method: :get" do
    with_inventory(@world) do
      calls = []
      Inventory.extensions.register_reorder_action(:stub, label: "Order these", path: ->(rows) { calls << rows; "/inventory" })
      sign_in @world.keeper.user
      get inventory_reorder_path(run: "stub", ticked: [ @world.screws.id ])
      assert_response :not_found
      assert_empty calls
    ensure
      Inventory.extensions.instance_variable_get(:@reorder_actions).delete(:stub)
    end
  end

  test "the POST needs a CSRF token" do
    with_inventory(@world) do
      calls = []
      Inventory.extensions.register_reorder_action(:stub, label: "Order these", path: ->(rows) { calls << rows; "/inventory" })
      sign_in @world.keeper.user
      ActionController::Base.allow_forgery_protection = true
      begin
        post inventory_reorder_path, params: { run: "stub", ticked: [ @world.screws.id ] }
      rescue ActionController::InvalidAuthenticityToken
        nil
      end
      assert_empty calls
    ensure
      ActionController::Base.allow_forgery_protection = false
      Inventory.extensions.instance_variable_get(:@reorder_actions).delete(:stub)
    end
  end

  test "a member can't run an action" do
    with_inventory(@world) do
      sign_in @world.member.user
      post inventory_reorder_path, params: { run: "csv", ticked: [ @world.screws.id ] }
      assert_redirected_to root_path
    end
  end

  test "register_reorder_action refuses a method other than get or post" do
    assert_raises(ArgumentError) { Inventory::Extensions.new.register_reorder_action(:x, label: "X", path: ->(_rows) { "/" }, method: :delete) }
  end
end
