# Ledgers with their team and balance, as the ledgers index lists them
# (LedgersController#index: policy_scope(Ledger)). Needs the ledger feature.
# The balance is Ledger#balance_cents, as the ledger page shows it.
class Mcp::Tools::ListLedgers < Mcp::Tool
  tool_name "list_ledgers"
  description "Ledgers you can see, with their team and balance, ordered by name."
  scope :read
  feature :ledger
  input_schema(properties: { limit: limit_property })
  output_schema(
    type: "object",
    properties: {
      items: {
        type: "array",
        items: {
          type: "object",
          properties: {
            id: { type: "string" },
            name: { type: [ "string", "null" ] },
            team: REF_SCHEMA,
            balance: { type: "object", properties: { cents: { type: "integer" }, formatted: { type: "string" } }, required: %w[cents formatted] }
          },
          required: %w[id name team balance]
        }
      },
      truncated: { type: "boolean" }
    },
    required: %w[items truncated]
  )

  def call(limit: DEFAULT_LIMIT)
    list(ctx.policy_scope(Ledger).includes(:team).order(:name, :id), limit: limit) do |ledger|
      { id: ledger.neat_id, name: ledger.name, team: team_json(ledger.team), balance: money_json(ledger.balance) }
    end
  end
end
