require "test_helper"
require_relative "../../../support/mcp_orders_world"

# The orders read tools show each viewer what their pages show them, and refuse where the
# pages refuse.
class Mcp::Tools::OrderReadsTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include McpOrdersWorld

  VIEWERS = %i[admin manager requester mentor teammate builder outsider buyer funding_manager parent].freeze

  setup do
    @draft = draft_request(@world, lines: [ { description: "Draft wheel", price: 5 } ])
    @submitted = submitted_request(@world, lines: [ { description: "Gearbox", price: 40 } ], purpose: "Drive train",
      estimated_shipping_cents: 700)
    @bought = approved_request(@world, lines: [ { description: "Bearing", price: 3, quantity: 4 }, { description: "Belt", price: 9 } ])
    @purchase = buy(@world, @bought.order_lines.to_a, vendor: @world.preferred_vendor, vendor_order_number: "PD-1", shipping_cents: 500)
    @art = submitted_request(@world, by: @world.outsider, team: @world.art, lines: [ { description: "Paint", price: 12 } ])
    @bought.follow!(@world.builder)
    @requests = [ @draft, @submitted, @bought, @art ]
  end

  def viewer(name)
    @world.public_send(name)
  end

  test "list_order_requests lists what Orders lists to each viewer, and My requests with mine" do
    VIEWERS.each do |name|
      on_page = linked_on_page(viewer(name), orders_requests_path, @requests) { |r| orders_request_path(r) }
      assert_equal on_page, ids_of(call_as(viewer(name), "list_order_requests", limit: 100)), name

      mine = linked_on_page(viewer(name), orders_requests_path(mine: 1), @requests) { |r| orders_request_path(r) }
      assert_equal mine, ids_of(call_as(viewer(name), "list_order_requests", mine: true, limit: 100)), name
    end

    assert_equal [ @bought.neat_id ], ids_of(call_as(@world.builder, "list_order_requests"))
    assert_equal [ @submitted.neat_id ], ids_of(call_as(@world.requester, "list_order_requests", status: "submitted"))
    assert_equal [ @submitted.neat_id ], ids_of(call_as(@world.mentor, "list_order_requests", waiting_on_me: true))
    assert_empty ids_of(call_as(@world.parent, "list_order_requests", waiting_on_me: true)), "a relative's request doesn't wait on them"
    assert_equal [ @art.neat_id ], ids_of(call_as(@world.admin, "list_order_requests", team_id: @world.art.neat_id))
  end

  test "list_order_requests leaves estimated shipping out of the total for those who don't see it, as the list does" do
    row = ->(person) { call_as(person, "list_order_requests", status: "submitted").value["items"].find { |item| item["id"] == @submitted.neat_id } }
    assert_equal 4000, row.call(@world.requester)["total"]["cents"]
    assert_equal 4700, row.call(@world.mentor)["total"]["cents"]
    assert_equal "Waiting for approval", row.call(@world.requester)["status_text"]
  end

  test "get_order_request opens for whoever the request page opens for" do
    VIEWERS.each do |name|
      @requests.each do |order_request|
        status, = page_for(viewer(name), orders_request_path(order_request))
        result = call_as(viewer(name), "get_order_request", order_request_id: order_request.neat_id)
        if status == 200
          assert_nil result.error, "#{name} #{order_request.display_title}"
        else
          assert_includes [ "Not found", "Not allowed" ], result.error, "#{name} #{order_request.display_title}"
        end
      end
    end
  end

  test "get_order_request shows items, purchases, followers and the timeline, and hides what the page hides" do
    result = call_as(@world.requester, "get_order_request", order_request_id: @bought.neat_id)
    assert_nil result.error
    request = result.value
    assert_equal %w[Bearing Belt], request["lines"].map { |line| line["description"] }
    assert_equal [ "Parts Depot" ], request["purchases"].map { |purchase| purchase["vendor_name"] }
    assert_equal [ @world.builder.neat_id ], request["followers"].map { |person| person["id"] }
    assert_equal %w[submitted approved purchased purchased], request["timeline"].map { |event| event["action"] }
    assert_not_includes request["timeline"].map { |event| event["action"] }, "followed"
    assert_nil request["estimated_shipping"]
    assert_nil request["decision"], "the requester isn't an approver"

    as_mentor = call_as(@world.mentor, "get_order_request", order_request_id: @submitted.neat_id).value
    assert_equal 700, as_mentor["estimated_shipping"]["cents"]
    assert_equal true, as_mentor["decision"]["can_decide"]
    assert_includes as_mentor["decision"]["flags"], "No funding source"

    as_parent = call_as(@world.parent, "get_order_request", order_request_id: @submitted.neat_id).value
    assert_equal false, as_parent["decision"]["can_decide"]
    assert_equal "A relative made this request, so another approver has to decide.", as_parent["decision"]["refusal"]
  end

  test "get_order_request shows funding sources only to those the page shows them to" do
    source = FundingSource.create!(team: @world.club, name: "Build budget", kind: :general, active: true)
    @submitted.edit!({ funding_source_id: source.id }, by: @world.mentor)

    assert_nil call_as(@world.requester, "get_order_request", order_request_id: @submitted.neat_id).value["funding_source"]
    assert_equal "Build budget", call_as(@world.mentor, "get_order_request", order_request_id: @submitted.neat_id).value["funding_source"]["name"]
    with_orders_settings(orders_requesters_pick_funding: "true") do
      assert_equal "Build budget", call_as(@world.requester, "get_order_request", order_request_id: @submitted.neat_id).value["funding_source"]["name"]
    end
  end

  test "orders_waiting_on_me lists the Home to-dos" do
    mentor = call_as(@world.mentor, "orders_waiting_on_me").value["items"]
    assert_equal [ [ "approve", @submitted.neat_id ] ], mentor.map { |todo| [ todo["kind"], todo.dig("order_request", "id") ] }

    @submitted.decide!(:changes_requested, by: @world.mentor, comment: "Which gearbox?")
    requester = call_as(@world.requester, "orders_waiting_on_me").value["items"]
    update = requester.find { |todo| todo["kind"] == "update" }
    assert_equal [ @submitted.neat_id, "Which gearbox?" ], [ update.dig("order_request", "id"), update["comment"] ]
    assert_equal 2, requester.find { |todo| todo["kind"] == "receive" }["count"]

    another = approved_request(@world, lines: [ { description: "Spacer", price: 1 } ])
    buyer = call_as(@world.buyer, "orders_waiting_on_me").value["items"]
    assert_equal [ another.order_lines.count ], buyer.select { |todo| todo["kind"] == "buy" }.map { |todo| todo["count"] }
    assert_empty call_as(@world.outsider, "orders_waiting_on_me").value["items"]
  end

  test "list_to_buy is the buyer's To buy page, and refused where that page is" do
    approved = approved_request(@world, lines: [ { description: "Spacer", price: 1, vendor_id: @world.other_vendor.id },
      { description: "Mystery part", price: 2 } ])
    @world.other_vendor.update!(account_note: "Customer 42")

    groups = call_as(@world.buyer, "list_to_buy").value["groups"]
    assert_equal [ "Vendor not chosen", "Hardware Barn" ], groups.map { |group| group["name"] }
    assert_equal [ approved.order_lines.second.neat_id ], groups.first["items"].map { |item| item["id"] }
    assert_equal "Customer 42", groups.second["account_note"]

    [ :requester, :mentor, :buyer, :manager, :outsider ].each do |name|
      status, = page_for(viewer(name), to_buy_orders_purchases_path)
      result = call_as(viewer(name), "list_to_buy")
      assert_equal status == 200, result.error.nil?, name
    end
  end

  test "list_purchases and get_purchase show the whole order to its buyer and only their own items to a requester" do
    VIEWERS.each do |name|
      on_page = linked_on_page(viewer(name), orders_purchases_path, [ @purchase ]) { |purchase| orders_purchase_path(purchase) }
      assert_equal on_page, ids_of(call_as(viewer(name), "list_purchases")), name

      status, = page_for(viewer(name), orders_purchase_path(@purchase))
      result = call_as(viewer(name), "get_purchase", purchase_id: @purchase.neat_id)
      assert_equal status == 200, result.error.nil?, name
    end

    full = call_as(@world.buyer, "get_purchase", purchase_id: @purchase.neat_id).value
    assert full["full"]
    assert_equal "PD-1", full["vendor_order_number"]
    assert_equal 2600, full["totals"]["total"]["cents"]
    assert_equal 1200, full["lines"].find { |line| line["description"] == "Bearing" }["cost"]["cents"]

    partial = call_as(@world.requester, "get_purchase", purchase_id: @purchase.neat_id).value
    assert_not partial["full"]
    assert_nil partial["totals"]
    assert_nil partial["vendor_order_number"]
    assert_equal [ nil ], partial["lines"].map { |line| line["cost"] }.uniq
    assert_nil call_as(@world.requester, "list_purchases").value["items"].first["total"]
  end

  test "list_vendors shows account notes and patterns only to those who manage vendors" do
    @world.preferred_vendor.update!(account_note: "Tax exempt")
    as_buyer = call_as(@world.buyer, "list_vendors").value["items"]
    as_requester = call_as(@world.requester, "list_vendors").value["items"]

    assert_equal [ "Parts Depot", "Hardware Barn" ], as_requester.map { |vendor| vendor["name"] }
    assert_equal "Tax exempt", as_buyer.first["account_note"]
    assert_equal "/p/([A-Z0-9-]+)", as_buyer.first["part_number_pattern"]
    assert_not as_requester.first.key?("account_note")
    assert_not as_requester.first.key?("part_number_pattern")
  end

  test "list_funding_sources and funding_source_report give the numbers only to those the pages give them to" do
    source = FundingSource.create!(team: @world.club, name: "Gift", kind: :restricted, restriction: "Robot parts only",
      giver: "A local foundation", amount_cents: 100_000, active: true)
    FundingSource.create!(team: @world.art, name: "Art budget", kind: :general, active: false)
    @bought.order_lines.each { |line| line.update_columns(funding_source_id: source.id) }

    requester = call_as(@world.requester, "list_funding_sources").value["items"]
    assert_equal [ "Gift", "Art budget" ], requester.map { |item| item["name"] }
    assert_nil requester.first["numbers"]
    assert_nil requester.first["giver"]
    assert_equal "Robot parts only", requester.first["restriction"]

    funder = call_as(@world.funding_manager, "list_funding_sources", include_inactive: false).value["items"]
    assert_equal [ "Gift" ], funder.map { |item| item["name"] }
    assert_equal 2600, funder.first["numbers"]["spent"]["cents"]
    assert_equal "A local foundation", funder.first["giver"]
    assert_equal [ "Gift" ], call_as(@world.funding_manager, "list_funding_sources", team_id: @world.robotics.neat_id).value["items"].map { |item| item["name"] }

    [ :requester, :mentor, :funding_manager, :outsider, :admin ].each do |name|
      status, = page_for(viewer(name), report_orders_funding_source_path(source))
      result = call_as(viewer(name), "funding_source_report", funding_source_id: source.neat_id)
      assert_equal status == 200, result.error.nil?, name
    end
    report = call_as(@world.funding_manager, "funding_source_report", funding_source_id: source.neat_id).value
    assert_equal %w[Bearing Belt], report["rows"].map { |row| row["item"] }.sort
    assert_equal 2600, report["total"]["cents"]
    assert_equal "Not allowed", call_as(@world.requester, "funding_source_report", funding_source_id: source.neat_id).error
  end
end
