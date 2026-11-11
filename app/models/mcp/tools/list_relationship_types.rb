# The relationship types, as RelationshipTypesController#index lists them (line 6).
# policy_scope(RelationshipType) is AdminPolicy::Scope, which returns every row, and that really
# is the rule (unfiltered: true): any signed-in member can open that page, which asks no index?.
# A type is two labels and a permission, with nothing about a person. Which types a viewer can
# actually add is the model's rule, run by add_relationship; permission says what it will ask.
class Mcp::Tools::ListRelationshipTypes < Mcp::Tool
  include Mcp::RelationshipRecords

  tool_name "list_relationship_types"
  description "The kinds of relationship between people: parent and child labels, who may add one (permission), and whether it makes the parent side a guardian."
  scope :read
  input_schema(properties: { limit: limit_property })
  output_schema(
    type: "object",
    properties: { items: { type: "array", items: Mcp::RelationshipRecords::TYPE_SCHEMA }, truncated: { type: "boolean" } },
    required: %w[items truncated]
  )

  def call(limit: DEFAULT_LIMIT)
    types = ctx.policy_scope(RelationshipType, unfiltered: true).order(:parent_label, :child_label, :id)
    list(types, limit: limit) { |type| relationship_type_json(type) }
  end
end
