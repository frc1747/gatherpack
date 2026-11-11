# MCP connector: forms. See config/initializers/mcp.rb.
# Answers and signatures stay out of the Rails log, on refused calls too. The last
# two aren't arguments of any tool, but a client may send them, and an undeclared
# argument is refused only after the log line.
Rails.application.config.filter_parameters += %w[answers typed_name answer signature]
  .map { |name| "params.arguments.#{name}" }

Rails.application.config.to_prepare do
  next unless Mcp.feature_registered?(:forms)

  Mcp.register_tool(Mcp::Tools::ListForms)
  Mcp.register_tool(Mcp::Tools::GetForm)
  Mcp.register_tool(Mcp::Tools::FormStatus)
  Mcp.register_tool(Mcp::Tools::FormAnswers)
  Mcp.register_tool(Mcp::Tools::SaveFormAnswers)
  Mcp.register_tool(Mcp::Tools::WithdrawFormResponse)
  Mcp.register_tool(Mcp::Tools::SignFormResponse)
end
