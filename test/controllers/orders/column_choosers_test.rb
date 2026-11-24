require "test_helper"
require "support/orders_world"

# The Columns chooser (BL-075) on the order tables.
class Orders::ColumnChoosersTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include OrdersWorld

  setup { @world = build_orders_world }

  test "each order table carries the column chooser and its key" do
    with_orders(@world) do
      source = FundingSource.create!(team: @world.robotics, name: "Parts Fund", kind: :general)
      approved_request(@world)
      sign_in @world.admin.user

      {
        orders_report_url("open") => "orders-report",
        report_orders_funding_source_url(source) => "orders-funding-report",
        to_buy_orders_purchases_url => "orders-to-buy",
        orders_funding_sources_url => "orders-funding-sources",
        orders_vendors_url => "orders-vendors"
      }.each do |url, key|
        get url
        assert_response :success, url
        assert_select "[data-controller~=column-chooser][data-column-chooser-key-value=?] table", key
      end
    end
  end
end
