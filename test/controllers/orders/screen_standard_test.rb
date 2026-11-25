require "test_helper"
require "support/orders_world"

# The orders screens on the screen standard (BL-069): filter pills, Cancel
# before the main button in grey, row buttons, table actions by the filters,
# and a breadcrumb on every page.
class Orders::ScreenStandardTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include OrdersWorld

  setup { @world = build_orders_world }

  test "Vendor orders filters by pills, and the old mine link still works" do
    with_orders(@world) do
      order_request = approved_request(@world)
      buy(@world, order_request.order_lines.to_a, vendor: @world.preferred_vendor)
      sign_in @world.buyer.user

      get orders_purchases_url
      assert_select "h1", "Vendor orders"
      assert_select ".screen-filter-bar a.btn-sm.btn-secondary[aria-current=true]", "All orders"
      assert_select ".screen-filter-bar a.btn-outline-secondary[href=?]", orders_purchases_path(status: "mine"), "Orders I placed"

      get orders_purchases_url(status: "mine")
      assert_select "h1", "Orders I placed"
      assert_select ".screen-filter-bar a[aria-current=true]", "Orders I placed"
      assert_match "Parts Depot", response.body

      get orders_purchases_url(mine: 1)
      assert_select "h1", "Orders I placed"
    end
  end

  test "To receive filters by pills, and the pills keep only mine on the way back" do
    with_orders(@world) do
      order_request = approved_request(@world)
      buy(@world, order_request.order_lines.to_a, vendor: @world.preferred_vendor)
      sign_in @world.requester.user

      get orders_deliveries_url
      assert_select ".orders-phone-only .screen-filter-bar a[aria-current=true]", "All I can receive"
      assert_select ".screen-filter-bar a[href=?]", orders_deliveries_path(status: "mine"), "Only mine"
      assert_select ".btn-lg", 0

      get orders_deliveries_url(status: "mine")
      assert_select ".screen-filter-bar a[aria-current=true]", "Only mine"
      line = order_request.order_lines.first
      assert_select "a.btn-primary[href=?]", new_orders_request_line_delivery_path(order_request, line, from: "list", mine: 1), "Receive"

      get new_orders_request_line_delivery_url(order_request, line, from: "list", mine: 1)
      labels = css_select(".gp-form-actions .btn").map { |node| node.text.presence || node["value"] }
      assert_equal [ "Cancel", "Record delivery" ], labels
      assert_select ".gp-form-actions a.btn-secondary[href=?]", orders_deliveries_path(mine: 1)
      assert_select ".gp-form-actions input.btn-primary[type=submit]"
      assert_select ".gp-form-actions .btn-lg, .gp-form-actions .btn-warning", 0
    end
  end

  test "new and edit pages for vendors, funding sources and approval steps end in a grey Cancel, then Save" do
    with_orders(@world) do
      source = FundingSource.create!(team: @world.robotics, name: "Build budget")
      step = ApprovalStep.find_by!(key: "approval")
      sign_in @world.admin.user

      [ new_orders_vendor_url, edit_orders_vendor_url(@world.preferred_vendor),
        new_orders_funding_source_url, edit_orders_funding_source_url(source),
        new_orders_approval_step_url, edit_orders_approval_step_url(step) ].each do |url|
        get url
        assert_response :success, url
        footer = css_select("form .card-footer").last
        buttons = footer.css(".btn")
        assert_equal "Cancel", buttons.first.text.strip, url
        assert_includes buttons.first["class"], "btn-secondary", url
        assert_includes buttons.last["class"], "btn-primary", url
        assert_select "form .btn-warning", { count: 0 }, url
      end
    end
  end

  test "approval step rows use small grey row buttons" do
    with_orders(@world) do
      step = ApprovalStep.find_by!(key: "approval")
      sign_in @world.admin.user

      get orders_approval_steps_url

      assert_select "##{ActionView::RecordIdentifier.dom_id(step)}" do
        assert_select "a.btn-sm.btn-outline-secondary[href=?]", edit_orders_approval_step_path(step), "Edit"
        assert_select "form button.btn-sm.btn-outline-secondary", "Retire"
        assert_select ".btn-outline-warning", 0
      end
    end
  end

  test "the link test has a breadcrumb opened on its own, and stays bare in the vendor form's frame" do
    with_orders(@world) do
      sign_in @world.buyer.user

      get pattern_test_orders_vendors_url, params: { url: "https://www.partsdepot.example/p/AB-12", pattern: "/p/([A-Z0-9-]+)" }
      assert_select ".breadcrumb", /Vendors.*Try a link/m
      assert_select "turbo-frame#pattern_test_result", /AB-12/

      get pattern_test_orders_vendors_url, params: { url: "https://www.partsdepot.example/p/AB-12", pattern: "/p/([A-Z0-9-]+)" },
        headers: { "Turbo-Frame" => "pattern_test_result" }
      assert_select ".breadcrumb", 0
      assert_select "turbo-frame#pattern_test_result", /AB-12/
    end
  end

  test "reports put Download CSV and Print at the right of the filter bar" do
    with_orders(@world) do
      source = FundingSource.create!(team: @world.robotics, name: "Build budget")
      sign_in @world.admin.user

      get orders_report_url("open")
      assert_select ".screen-filter-bar .ms-auto a.btn-secondary[href=?]", orders_report_path("open", format: :csv), "Download CSV"
      assert_select ".screen-filter-bar .ms-auto button.btn-dark[type=button][data-action=?]", "print#print", "Print"

      get report_orders_funding_source_url(source)
      assert_select ".screen-filter-bar .ms-auto a.btn-secondary[href=?]", report_orders_funding_source_path(source, format: :csv), "Download CSV"
      assert_select ".screen-filter-bar .ms-auto button.btn-dark[data-controller=print]", "Print"
    end
  end
end
