require "test_helper"
require "support/inventory_world"

class Inventory::MovementsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include InventoryWorld

  setup do
    host! "localhost"
    @world = build_inventory_world
  end

  test "a member records used and is offered Undo" do
    with_inventory(@world) do
      stock!(@world, 10)
      sign_in @world.member.user
      get new_inventory_movement_path(kind: "used", item_id: @world.screws.id)
      assert_response :success
      post inventory_movements_path, params: { kind: "used", item_id: @world.screws.id, location_id: @world.bin1.id, quantity: "4" }
      assert_redirected_to inventory_item_path(@world.screws)
      assert_equal 6, @world.screws.stock_at(@world.bin1)
      follow_redirect!
      assert_select ".inventory-toast", text: /Used 4 from Bin 1/
      assert_select ".inventory-toast button", text: "Undo"
    end
  end

  test "a member moves stock between places" do
    with_inventory(@world) do
      stock!(@world, 10)
      sign_in @world.member.user
      post inventory_movements_path, params: { kind: "moved", item_id: @world.screws.id, location_id: @world.bin1.id,
        to_location_id: @world.bin2.id, quantity: "3" }
      assert_equal 7, @world.screws.stock_at(@world.bin1)
      assert_equal 3, @world.screws.stock_at(@world.bin2)
    end
  end

  test "a member can't record removed by default" do
    with_inventory(@world) do
      stock!(@world, 10)
      sign_in @world.member.user
      assert_no_difference -> { StockMovement.count } do
        post inventory_movements_path, params: { kind: "removed", item_id: @world.screws.id, location_id: @world.bin1.id,
          quantity: "1", reason: "Lost" }
      end
    end
  end

  test "a refused change shows the form again with the reason" do
    with_inventory(@world) do
      sign_in @world.keeper.user
      post inventory_movements_path, params: { kind: "removed", item_id: @world.screws.id, location_id: @world.bin1.id, quantity: "1" }
      assert_response :unprocessable_entity
      assert_select ".alert-danger", text: "Give a reason"
    end
  end

  test "a manager records received with where it came from" do
    with_inventory(@world) do
      sign_in @world.keeper.user
      post inventory_movements_path, params: { kind: "received", item_id: @world.screws.id, location_id: @world.bin1.id,
        quantity: "50", reason: "Parts Depot" }
      assert_equal 50, @world.screws.stock_at(@world.bin1)
      assert_equal "Parts Depot", StockMovement.received.last.reason
    end
  end

  test "the recorder undoes their own change" do
    with_inventory(@world) do
      stock!(@world, 10)
      used = record(@world, :used, 2, person: @world.member)
      sign_in @world.member.user
      post undo_inventory_movement_path(used)
      assert used.undone?
      assert_equal 10, @world.screws.stock_at(@world.bin1)
    end
  end

  test "a teammate can't undo someone else's change" do
    with_inventory(@world) do
      stock!(@world, 10)
      used = record(@world, :used, 2, person: @world.member)
      sign_in @world.teammate.user
      post undo_inventory_movement_path(used)
      assert_not used.undone?
    end
  end

  test "Changes is for managers, filters by kind and downloads as CSV" do
    with_inventory(@world) do
      stock!(@world, 10)
      record(@world, :used, 2, person: @world.member)
      record(@world, :counted, 3, person: @world.member)

      sign_in @world.member.user
      get inventory_movements_path
      assert_redirected_to root_path

      sign_in @world.keeper.user
      get inventory_movements_path(kind: "counted")
      assert_response :success
      assert_select ".inventory-history li", count: 1
      assert_select ".inventory-big-count", text: /Counted 3 at Bin 1/

      get inventory_movements_path(format: :csv)
      assert_equal "text/csv", response.media_type
      rows = CSV.parse(response.body, headers: true)
      assert_equal %w[Counted Used Added], rows.map { |row| row["Kind"] }
    end
  end
end
