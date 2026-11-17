# MCP connector: orders. See config/initializers/mcp.rb. Registers only when the orders feature
# exists in this build; each tool also requires it to be on. Runs after mcp.rb, which resets the
# registry, but before orders.rb, which registers the feature, so it looks for the feature's
# code rather than Mcp.feature_registered?.
#
# Comments on a decision or an item, reasons for cancelling or moving one, and an item's note on
# a new request can say anything about members, so they stay out of the Rails log, on refused
# calls too. Matches both the params and the wrapper's copy; a request's items keep their key
# path inside the list. mcp.rb already filters note. This covers MCP calls only: the pages' own
# params aren't filtered here.
Rails.application.config.filter_parameters += %w[comment reason lines.note lines.other_vendor_reason]
  .map { |name| "params.arguments.#{name}" }

Rails.application.config.to_prepare do
  next unless defined?(OrderRequest)

  # Reads
  Mcp.register_tool(Mcp::Tools::ListOrderRequests)
  Mcp.register_tool(Mcp::Tools::GetOrderRequest)
  Mcp.register_tool(Mcp::Tools::OrdersWaitingOnMe)
  Mcp.register_tool(Mcp::Tools::ListToBuy)
  Mcp.register_tool(Mcp::Tools::ListPurchases)
  Mcp.register_tool(Mcp::Tools::GetPurchase)
  Mcp.register_tool(Mcp::Tools::ListVendors)
  Mcp.register_tool(Mcp::Tools::ListOrderLists)
  Mcp.register_tool(Mcp::Tools::ListFundingSources)
  Mcp.register_tool(Mcp::Tools::FundingSourceReport)

  # Writes
  Mcp.register_tool(Mcp::Tools::CreateOrderRequest)
  Mcp.register_tool(Mcp::Tools::DecideOrderRequest)
  Mcp.register_tool(Mcp::Tools::RecordPurchase)
  Mcp.register_tool(Mcp::Tools::UpdateOrderLine)
  Mcp.register_tool(Mcp::Tools::RecordDelivery)
  Mcp.register_tool(Mcp::Tools::SetFundingSource)
end
