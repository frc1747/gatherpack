require "test_helper"
require "support/orders_world"

# BL-077 Duplicate on a request's page, and the Columns chooser (BL-075) on
# the order tables.
class Orders::DuplicateAndColumnsTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include OrdersWorld

  setup { @world = build_orders_world }

  def more_items
    css_select(".screen-action-row .dropdown-menu > li:not(.d-md-none)").map { |node| node.text.strip }
  end

  test "duplicating copies the request and its lines into a new draft and leaves the rest behind" do
    with_orders(@world) do
      source = FundingSource.create!(team: @world.robotics, name: "Parts Fund", kind: :general)
      original = submitted_request(@world, title: "Gears", purpose: "Drive", funding_source: source,
        lines: [ { description: "Gear", price: 10, quantity: 3, url: "https://shop.example/gear", note: "Steel" } ])
      original.decide!(:approved, by: @world.mentor)
      original.follow!(@world.teammate)
      buy(@world, original.order_lines.reload, vendor: @world.preferred_vendor)
      sign_in @world.teammate.user

      assert_difference -> { OrderRequest.count } => 1, -> { OrderLine.count } => 1 do
        post duplicate_orders_request_url(original)
      end

      copy = OrderRequest.order(:created_at).last
      assert_redirected_to edit_orders_request_url(copy)
      assert_equal "Duplicated. Check it, then save.", flash[:notice]
      assert copy.draft?
      assert_equal @world.teammate, copy.requested_by
      assert_equal [ original.team, source, "Gears (copy)", "Drive" ], [ copy.team, copy.funding_source, copy.title, copy.purpose ]
      line = copy.order_lines.sole
      source_line = original.order_lines.first
      assert_equal %w[Gear 3 https://shop.example/gear Steel], [ line.description, line.quantity.to_s, line.url, line.note ]
      assert_equal source_line.estimated_unit_price_cents, line.estimated_unit_price_cents
      assert_not_equal source_line.id, line.id
      assert line.pending?
      assert_nil line.purchase_id
      assert_empty copy.order_approvals
      assert_empty copy.order_request_watchers
      assert_empty copy.events
      assert_equal 1, original.reload.order_request_watchers.count
      assert original.order_lines.first.purchase_id
    end
  end

  test "someone who can't ask for the team, or can't see the request, is refused" do
    with_orders(@world) do
      original = submitted_request(@world)

      sign_in @world.outsider.user
      assert_no_difference -> { OrderRequest.count } do
        post duplicate_orders_request_url(original)
      end
      assert_response :not_found

      # A follower who can see it but may not request for another team's.
      other = submitted_request(@world, by: @world.outsider, team: @world.art)
      other.follow!(@world.mentor)
      sign_in @world.mentor.user
      get orders_request_url(other)
      assert_response :success
      assert_select ".dropdown-menu", text: /Duplicate/, count: 0
      assert_no_difference -> { OrderRequest.count } do
        post duplicate_orders_request_url(other)
      end
      assert_response :redirect
    end
  end

  test "Duplicate is a More item on the request's page, before Print" do
    with_orders(@world) do
      original = submitted_request(@world)
      sign_in @world.requester.user

      get orders_request_url(original)

      assert_includes more_items, "Duplicate"
      assert_operator more_items.index("Duplicate"), :<, more_items.index("Print")
      assert_select ".screen-action-row .dropdown-menu form[action=?]", duplicate_orders_request_path(original)
      assert_select ".screen-action-row > a.btn, .screen-action-row > form > button.btn", text: "Duplicate", count: 0
    end
  end

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
