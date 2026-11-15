require "test_helper"
require "support/orders_world"

class Orders::ReportsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include OrdersWorld

  setup { @world = build_orders_world }

  test "the list is for people who run orders" do
    with_orders(@world) do
      [ @world.admin, @world.manager, @world.mentor, @world.buyer, @world.funding_manager ].each do |person|
        sign_in person.user
        get orders_reports_url
        assert_response :success, person.display_name
        assert_match "Open requests", response.body
      end
      [ @world.requester, @world.teammate, @world.outsider ].each do |person|
        sign_in person.user
        get orders_reports_url
        assert_redirected_to root_url
        get orders_report_url("open")
        assert_redirected_to root_url
      end
    end
  end

  test "an unknown report is not found" do
    with_orders(@world) do
      sign_in @world.admin.user
      get orders_report_url("nonsense")
      assert_response :not_found
    end
  end

  test "open requests by status and age" do
    with_orders(@world) do
      fresh = submitted_request(@world, title: "Fresh one")
      old = submitted_request(@world, title: "Old one")
      old.update_columns(submitted_at: 40.days.ago)
      approved_request(@world, title: "Approved one")
      draft_request(@world, title: "Still a draft")
      sign_in @world.admin.user

      get orders_report_url("open")
      assert_response :success
      assert_select "h1", "Open requests"
      assert_select "tr", text: /Waiting for approval\s*2\s*1\s*0\s*0\s*1/
      assert_match "Old one", response.body
      assert_no_match "Still a draft", response.body
      assert_operator response.body.index("Old one"), :<, response.body.index("Fresh one")
      assert_equal fresh.team, @world.robotics
    end
  end

  test "spending by store, team and month splits shipping and tax" do
    with_orders(@world) do
      request = approved_request(@world, lines: [ { description: "Motor", quantity: 2, price: 30 }, { description: "Wire", price: 40 } ])
      buy(@world, request.order_lines, vendor: @world.preferred_vendor, ordered_on: Date.new(2026, 10, 5), shipping_cents: 1000, tax_cents: 500)
      sign_in @world.admin.user

      get orders_report_url("spending", format: :csv)
      assert_response :success
      csv = CSV.parse(response.body)
      assert_includes csv, [ "Parts Depot", "2", "100.00", "10.00", "5.00", "115.00" ]
      assert_includes csv, [ @world.robotics.name, "2", "100.00", "10.00", "5.00", "115.00" ]
      assert_includes csv, [ "October 2026", "2", "100.00", "10.00", "5.00", "115.00" ]
    end
  end

  test "overdue items are lines still waiting past the needed-by date" do
    with_orders(@world) do
      late = approved_request(@world, title: "Late one", needed_by: Date.current - 3, lines: [ { description: "Late part", price: 5 } ])
      approved_request(@world, title: "On time", needed_by: Date.current + 3, lines: [ { description: "Fine part", price: 5 } ])
      approved_request(@world, title: "No rush", lines: [ { description: "Whenever part", price: 5 } ])
      sign_in @world.admin.user

      get orders_report_url("overdue")
      assert_match "Late part", response.body
      assert_no_match "Fine part", response.body
      assert_no_match "Whenever part", response.body
      assert_select "td", text: "3"
      assert_equal "Late one", late.title
    end
  end

  test "non-preferred spending leaves out preferred stores" do
    with_orders(@world) do
      request = approved_request(@world, lines: [ { description: "Preferred thing", price: 10 }, { description: "Corner thing", price: 20 } ])
      preferred, corner = request.order_lines.to_a
      buy(@world, [ preferred ], vendor: @world.preferred_vendor)
      buy(@world, [ corner ], vendor: nil)
      sign_in @world.admin.user

      get orders_report_url("non_preferred", format: :csv)
      csv = CSV.parse(response.body)
      assert_includes csv, [ "Corner Store", "1", "20.00", "0.00", "0.00", "20.00" ]
      assert_not csv.flatten.include?("Parts Depot")
    end
  end

  test "each report prints and downloads" do
    with_orders(@world) do
      sign_in @world.admin.user
      Orders::Reports::KEYS.each do |key|
        get orders_report_url(key)
        assert_response :success
        assert_select "[data-controller=print]"
        get orders_report_url(key, format: :csv)
        assert_equal "text/csv", response.media_type
        assert_match(/orders-/, response.headers["Content-Disposition"])
      end
    end
  end

  test "CSV text that looks like a formula is quoted" do
    assert_equal "'=SUM(A1)", Orders::Reports.csv_value("=SUM(A1)")
    assert_equal "Gear", Orders::Reports.csv_value("Gear")
  end

  test "a team manager sees only the requests of the teams they staff" do
    with_orders(@world) do
      submitted_request(@world, title: "Robotics ask")
      submitted_request(@world, title: "Art ask", by: @world.outsider, team: @world.art)
      sign_in @world.manager.user

      get orders_report_url("open")
      assert_match "Robotics ask", response.body
      assert_no_match "Art ask", response.body
    end
  end
end
