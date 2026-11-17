require "test_helper"
require "support/inventory_world"

class Inventory::ImportsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include InventoryWorld

  setup do
    host! "localhost"
    @world = build_inventory_world
  end

  test "a manager previews a file, then imports it" do
    with_inventory(@world) do
      sign_in @world.keeper.user
      get new_inventory_import_path
      assert_response :success

      file = Rack::Test::UploadedFile.new(StringIO.new("Name,Place code,Quantity\nZip tie,A-2,6\nTape,Q-1,1\n"), "text/csv",
        original_filename: "items.csv")
      assert_no_difference -> { Item.count } do
        post inventory_import_path, params: { team_id: @world.robotics.id, file: file }
      end
      assert_response :unprocessable_entity
      assert_select "#import-summary", text: /1 new item, 0 items to update, 1 row skipped/
      assert_select "#import-problems", text: /Unknown place code Q-1/

      csv = css_select("input[name=csv]").first["value"]
      post inventory_import_path, params: { team_id: @world.robotics.id, csv: csv, confirm: "1" }
      assert_redirected_to inventory_items_path
      assert_equal 6, Item.find_by!(name: "Zip tie").stock_at(@world.bin2)
    end
  end

  test "members can't import" do
    with_inventory(@world) do
      sign_in @world.member.user
      post inventory_import_path, params: { team_id: @world.robotics.id, csv: "Name\nZip tie\n", confirm: "1" }
      assert_redirected_to root_path
      assert_not Item.exists?(name: "Zip tie")
    end
  end
end
