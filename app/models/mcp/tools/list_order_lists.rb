# The lists a group manages for orders, as the pages offer them: payment methods (the Record purchase
# form's choices; buyers), delivery problems (the Receive form's choices; anyone signed in, as the
# form is) and the approval steps (admins and whoever the list's registration allows, as the Approval
# Steps screen is). Only active rows, in picker order. They are what record_purchase and
# record_delivery take IDs of. Needs the orders feature.
class Mcp::Tools::ListOrderLists < Mcp::Tool
  include Mcp::OrderRecords

  tool_name "list_order_lists"
  description "The group's order lists, active rows in picker order: payment_methods (with reimburse; buyers only), " \
    "delivery_problems and approval_steps (with minimum_cents; admins only). Use their IDs, or names, in record_purchase " \
    "and record_delivery."
  scope :read
  feature :orders
  input_schema(properties: {})
  output_schema(
    type: "object",
    properties: {
      payment_methods: { type: "array", items: Mcp::OrderRecords::PAYMENT_METHOD_SCHEMA },
      delivery_problems: { type: "array", items: Mcp::OrderRecords::PROBLEM_KIND_SCHEMA },
      approval_steps: {
        type: "array",
        items: {
          type: "object",
          properties: { id: { type: "string" }, name: { type: "string" }, minimum_cents: { type: "integer" } },
          required: %w[id name minimum_cents]
        }
      }
    },
    required: %w[payment_methods delivery_problems approval_steps]
  )

  def call
    Orders::Lists.seed!
    {
      payment_methods: (PaymentMethod.active.ordered.map { |method| payment_method_json(method) } if ctx.allowed?(Purchase, :create?)).to_a,
      delivery_problems: DeliveryProblemKind.active.ordered.map { |kind| problem_kind_json(kind) },
      approval_steps: approval_steps
    }
  end

  private

  def approval_steps
    return [] unless ctx.allowed?(ApprovalStep, :index?, policy_class: ManagedListPolicy)

    ApprovalStep.active.ordered.map { |step| { id: step.neat_id, name: step.name, minimum_cents: step.minimum_cents } }
  end
end
