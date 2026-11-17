# Removes a token, as TokensController#destroy does (line 51): set_token (line 58, in
# policy_scope(Token), then destroy?, which is create?: admins and managers), and destroy!.
class Mcp::Tools::RemoveToken < Mcp::Tool
  include Mcp::TokenRecords

  tool_name "remove_token"
  description "Take a scan card or tag away, as Delete does on the token's page, for admins and managers; a member gets \"Not allowed\" for their own, and \"Not found\" for one they can't see. Returns what was removed, masked."
  scope :write
  feature :tokens
  destructive
  input_schema(
    properties: { token_id: { type: "string", description: "The token's ID (tok_)" } },
    required: %w[token_id]
  )
  output_schema(Mcp::TokenRecords::SCHEMA.merge(
    properties: Mcp::TokenRecords::SCHEMA[:properties].merge(removed: { type: "boolean" }),
    required: Mcp::TokenRecords::SCHEMA[:required] + %w[removed]
  ))

  def call(token_id:)
    token = ctx.find(Token, token_id)
    ctx.authorize!(token, :destroy?)
    token.destroy!

    changed!(token)
    token_json(token).merge(removed: true)
  end
end
