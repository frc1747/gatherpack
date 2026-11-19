require "test_helper"
require "support/inventory_world"

# Inventory's lists on the shared list screen (/lists/<key>): what they
# refuse is said on the screen, not as an error page.
class Inventory::ListScreensTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include InventoryWorld

  setup do
    host! "localhost"
    @world = build_inventory_world
  end

  def as_admin(&block)
    with_inventory(@world) do
      sign_in @world.admin.user
      block.call
    end
  end

  test "every inventory list screen opens, with a retired row too" do
    skip "needs feature/managed-lists" unless defined?(GatherPack::ManagedLists)

    as_admin do
      %i[location_types stock_units unit_conditions reading_types].each do |key|
        list = GatherPack::ManagedLists.find(key)
        list.model.ordered.last.update_columns(active: false) if list.model.where(key: nil).none?
        get managed_list_path(key)
        assert_response :success, "#{key} list screen"
      end
    end
  end

  test "retiring the default stock unit says to pick another default first" do
    pack = stock_unit("pack")
    pack.update!(default: true)
    as_admin do
      patch retire_managed_list_row_path(:stock_units, pack)
      assert_redirected_to managed_list_path(:stock_units)
      assert_equal "pack is the default unit: make another unit the default before retiring it", flash[:danger]
      assert pack.reload.active?

      stock_unit("box").update!(default: true)
      patch retire_managed_list_row_path(:stock_units, pack)
      assert_not pack.reload.active?
    end
  end

  test "merging the default stock unit away is refused" do
    spool = StockUnit.create!(name: "spool")
    @world.screws.update!(stock_unit: spool)
    spool.update!(default: true)
    as_admin do
      post merge_managed_list_row_path(:stock_units, spool), params: { target_id: stock_unit("roll").id }
      assert_redirected_to managed_list_path(:stock_units)
      assert_match(/spool is the default unit/, flash[:danger])
      assert StockUnit.exists?(spool.id)
    end
  end

  test "unticking Keeps stock on a type whose places hold stock is refused on its edit form" do
    stock!(@world, 5)
    storage = location_type("storage")
    as_admin do
      patch managed_list_row_path(:location_types, storage), params: { row: { name: "Storage", holds_stock: "0" } }
      assert_response :unprocessable_entity
      assert_match "Counted stock is kept in storage places: move or remove it first", response.body
      assert storage.reload.holds_stock?
    end
  end

  test "merging place types that do different things is refused" do
    cart = LocationType.create!(name: "Cart")
    stand = LocationType.create!(name: "Stand", holds_stock: false, holds_installed_parts: true)
    Location.create!(team: @world.club, name: "Stand 1", location_type: stand)
    as_admin do
      post merge_managed_list_row_path(:location_types, stand), params: { target_id: cart.id }
      assert_redirected_to managed_list_path(:location_types)
      assert_match(/same way/, flash[:danger])
      assert LocationType.exists?(stand.id)
    end
  end
end
