require "test_helper"
require "support/orders_world"

class Orders::VendorsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include OrdersWorld

  setup { @world = build_orders_world }

  test "anyone signed in sees the list, without the account note" do
    with_orders(@world) do
      @world.preferred_vendor.update!(account_note: "Customer 4411")
      sign_in @world.requester.user

      get orders_vendors_url
      assert_response :success
      assert_match "Parts Depot", response.body

      get orders_vendor_url(@world.preferred_vendor)
      assert_response :success
      assert_no_match "Customer 4411", response.body
      assert_select "a", text: "Edit", count: 0
    end
  end

  test "a buyer sees the account note and the pattern" do
    with_orders(@world) do
      @world.preferred_vendor.update!(account_note: "Customer 4411")
      sign_in @world.buyer.user

      get orders_vendor_url(@world.preferred_vendor)
      assert_match "Customer 4411", response.body
      assert_match "/p/([A-Z0-9-]+)", CGI.unescapeHTML(response.body)
    end
  end

  test "a requester can't create, change or delete a vendor" do
    with_orders(@world) do
      sign_in @world.requester.user

      get new_orders_vendor_url
      assert_redirected_to root_url
      assert_no_difference "Vendor.count" do
        post orders_vendors_url, params: { vendor: { name: "Sneaky" } }
      end
      patch orders_vendor_url(@world.preferred_vendor), params: { vendor: { name: "Renamed" } }
      assert_equal "Parts Depot", @world.preferred_vendor.reload.name
      assert_no_difference "Vendor.count" do
        delete orders_vendor_url(@world.other_vendor)
      end
    end
  end

  test "a buyer creates a vendor from comma separated domains" do
    with_orders(@world) do
      sign_in @world.buyer.user

      assert_difference "Vendor.count", 1 do
        post orders_vendors_url, params: { vendor: { name: "Metal Mart", domains: "metalmart.example, www.metals.example",
          part_number_pattern: "item=(\\d+)", preferred: "1", active: "1" } }
      end
      vendor = Vendor.find_by!(name: "Metal Mart")
      assert_redirected_to orders_vendor_url(vendor)
      assert_equal %w[metalmart.example metals.example], vendor.domains
      assert vendor.preferred?
    end
  end

  test "a pattern that doesn't compile is refused" do
    with_orders(@world) do
      sign_in @world.buyer.user

      assert_no_difference "Vendor.count" do
        post orders_vendors_url, params: { vendor: { name: "Broken", part_number_pattern: "(" } }
      end
      assert_response :unprocessable_entity
    end
  end

  test "a team manager and an admin can edit and delete" do
    with_orders(@world) do
      sign_in @world.manager.user
      patch orders_vendor_url(@world.other_vendor), params: { vendor: { name: "Barn", active: "0" } }
      assert_redirected_to orders_vendor_url(@world.other_vendor)
      assert_equal "Barn", @world.other_vendor.reload.name
      assert_not @world.other_vendor.active?

      sign_in @world.admin.user
      assert_difference "Vendor.count", -1 do
        delete orders_vendor_url(@world.other_vendor)
      end
    end
  end

  test "a vendor that has been used can't be deleted" do
    with_orders(@world) do
      request = approved_request(@world, lines: [ { description: "Gear", price: 10, vendor: @world.preferred_vendor } ])
      assert request.order_lines.first.vendor
      sign_in @world.admin.user

      assert_no_difference "Vendor.count" do
        delete orders_vendor_url(@world.preferred_vendor)
      end
      assert_redirected_to orders_vendor_url(@world.preferred_vendor)
      assert_match "can't be deleted", flash[:alert]
      assert_match "Untick In use", flash[:alert]
    end
  end

  test "the link test shows the matching vendor and the part number" do
    with_orders(@world) do
      sign_in @world.buyer.user

      get pattern_test_orders_vendors_url, params: { url: "https://www.partsdepot.example/p/AB-12?x=1", pattern: "/p/([A-Z0-9-]+)" }
      assert_response :success
      assert_match "Parts Depot", response.body
      assert_match "AB-12", response.body
    end
  end

  test "the link test says so when nothing matches or the pattern is bad" do
    with_orders(@world) do
      sign_in @world.buyer.user

      get pattern_test_orders_vendors_url, params: { url: "https://elsewhere.example/thing", pattern: "/p/(\\d+)" }
      assert_match "Other store", response.body
      assert_match "Nothing found", response.body

      get pattern_test_orders_vendors_url, params: { url: "https://elsewhere.example/thing", pattern: "(" }
      assert_match "valid regular expression", response.body
    end
  end

  test "the link test is for people who manage vendors" do
    with_orders(@world) do
      sign_in @world.requester.user

      get pattern_test_orders_vendors_url, params: { url: "https://partsdepot.example/p/1" }
      assert_redirected_to root_url
    end
  end

  test "vendors are turned away while orders are off" do
    sign_in @world.buyer.user
    with_settings(orders_settings(@world, feature_orders: "false")) do
      get orders_vendors_url
      assert_redirected_to root_url
    end
  end
end
