require_relative "mcp_world"
require_relative "order_inventory_world"

# The orders and inventory world (order_inventory_world.rb) for the MCP orders and inventory
# tools, with McpWorld's tool helpers. Each test gets MCP, orders and inventory turned on, with
# the world's approver, buyer, funding manager and inventory keeper grants:
#
#   club > robotics (requester, mentor: approver, teammate, buyer: buyer and keeper, funder,
#          parent: approver and a relative of the requester; manager manages it) > build (builder)
#   art (outsider); admin
#
#   call_as(@world.mentor, "get_order_request", order_request_id: ...)   # => Mcp::Tool::Result
#   page_shows?(@world.requester, orders_requests_path) { |body| ... }  # signs in, GETs, signs out
module McpOrdersWorld
  def self.included(base)
    base.include McpWorld
    base.include OrderInventoryWorld
    base.setup do
      host! "localhost" if respond_to?(:host!)
      @world, @stock = build_order_inventory_world
      @restore_orders = apply_settings(mcp_orders_settings)
      reset_orders_caches
    end
    base.teardown do
      @restore_orders&.call
      reset_orders_caches
    end
  end

  def mcp_orders_settings(**overrides)
    orders_settings(@world).merge(feature_inventory: "true",
      inventory_managers: "#{@stock.keeper_badge.name} > #{@world.club.name}").merge(overrides)
  end

  # Settings for the block on top of the world's, with the per-request caches cleared.
  def with_orders_settings(**overrides, &block)
    with_settings(overrides) do
      reset_orders_caches
      block.call
    ensure
      reset_orders_caches
    end
  end

  def reset_orders_caches
    Orders::Current.reset
    Inventory::Current.reset
  end

  def call_as(person, name, **arguments)
    reset_orders_caches
    call_tool(name, user: person.user, **arguments)
  end

  # The page for this person: its status and body.
  def page_for(person, path)
    reset_orders_caches
    sign_in person.user
    get path
    [ response.status, response.body ]
  ensure
    sign_out person.user
    reset_orders_caches
  end

  # The neat IDs of records whose page path the person's page links to.
  def linked_on_page(person, page_path, records, &path_for)
    status, body = page_for(person, page_path)
    return nil unless status == 200

    records.select { |record| body.include?("\"#{path_for.call(record)}\"") || body.include?("\"#{path_for.call(record)}/") }.map(&:neat_id).sort
  end

  def ids_of(result)
    assert_nil result.error
    result.value["items"].map { |item| item["id"] }.sort
  end
end
