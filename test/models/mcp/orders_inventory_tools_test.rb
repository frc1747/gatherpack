require "test_helper"
require_relative "../../support/mcp_orders_world"

# The orders and inventory connectors: which tools they add, and the gates every tool has.
class Mcp::OrdersInventoryToolsTest < ActionDispatch::IntegrationTest
  include McpOrdersWorld

  ORDERS_TOOLS = %w[
    list_order_requests get_order_request orders_waiting_on_me list_to_buy list_purchases get_purchase list_vendors
    list_funding_sources funding_source_report create_order_request decide_order_request record_purchase update_order_line
    record_delivery set_funding_source
  ].freeze
  INVENTORY_TOOLS = %w[list_items get_item list_locations reorder_list list_machines get_unit record_stock_movement record_unit_event].freeze
  WRITES = %w[
    create_order_request decide_order_request record_purchase update_order_line record_delivery set_funding_source
    record_stock_movement record_unit_event
  ].freeze

  def names(tools)
    tools.map(&:tool_name)
  end

  test "registers 15 orders tools and 8 inventory tools, each gated on its feature" do
    orders = Mcp.tools.select { |tool| tool.features == [ :orders ] }
    inventory = Mcp.tools.select { |tool| tool.features == [ :inventory ] }
    assert_equal ORDERS_TOOLS.sort, names(orders).sort
    assert_equal INVENTORY_TOOLS.sort, names(inventory).sort
    assert_equal WRITES.sort, names((orders + inventory).select(&:write?)).sort
  end

  test "tools/list shows them while their feature is on" do
    ctx = mcp_context(@world.admin.user, scopes: "mcp_write")
    with_settings(mcp_write_enabled: "true") do
      assert_empty (ORDERS_TOOLS + INVENTORY_TOOLS) - names(Mcp.available_tools(ctx))

      with_feature(:orders, false) do
        assert_empty ORDERS_TOOLS & names(Mcp.available_tools(ctx))
        assert_empty INVENTORY_TOOLS - names(Mcp.available_tools(ctx))
        assert_equal "Feature off", call_as(@world.admin, "list_order_requests").error
      end
      with_feature(:inventory, false) do
        assert_empty INVENTORY_TOOLS & names(Mcp.available_tools(ctx))
        assert_equal "Feature off", call_as(@world.admin, "list_items").error
      end
    end
  end

  test "every write is refused while MCP changes are off, or without the write scope" do
    WRITES.each do |name|
      result = call_tool(name, user: @world.admin.user, writes_enabled: false)
      assert_equal "Writes disabled", result.error, name
      assert_equal :denied, result.outcome, name
      assert_equal "Not allowed", call_tool(name, user: @world.admin.user, scopes: "mcp_read").error, name
    end
  end

  test "a refused write changes nothing" do
    order_request = submitted_request(@world)
    result = call_tool("decide_order_request", user: @world.mentor.user, writes_enabled: false,
      order_request_id: order_request.neat_id, decision: "approve")
    assert_equal "Writes disabled", result.error
    assert_predicate order_request.reload, :submitted?
  end

  test "comments and reasons stay out of the Rails log" do
    filter = ActiveSupport::ParameterFilter.new(Rails.application.config.filter_parameters)
    filtered = filter.filter("params" => { "arguments" => { "comment" => "c", "reason" => "r", "note" => "n", "purpose" => "p",
      "lines" => [ { "note" => "n", "other_vendor_reason" => "r", "description" => "d" } ] } })
    arguments = filtered["params"]["arguments"]
    assert_equal [ "[FILTERED]" ] * 3, arguments.values_at("comment", "reason", "note")
    assert_equal [ "[FILTERED]", "[FILTERED]", "d" ], arguments["lines"].first.values_at("note", "other_vendor_reason", "description")
  end
end
