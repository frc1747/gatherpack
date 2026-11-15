# What the relationship tools share: a relationship type as list_relationship_types shows
# it, and a relationship with both people.
module Mcp::RelationshipRecords
  TYPE_SCHEMA = {
    type: "object",
    properties: {
      id: { type: "string" },
      parent_label: { type: %w[string null] },
      child_label: { type: %w[string null] },
      permission: { type: "string" },
      guardianship: { type: "boolean" }
    },
    required: %w[id parent_label child_label permission guardianship]
  }.freeze

  SCHEMA = {
    type: "object",
    properties: {
      id: { type: "string" },
      relationship_type: TYPE_SCHEMA,
      parent: Mcp::Tool::REF_SCHEMA,
      child: Mcp::Tool::REF_SCHEMA
    },
    required: %w[id relationship_type parent child]
  }.freeze

  private

  # Guardianship exists only on a build with person fields: without one, no type grants it.
  def relationship_type_json(type)
    {
      id: type.neat_id,
      parent_label: type.parent_label,
      child_label: type.child_label,
      permission: type.permission,
      guardianship: type.try(:guardianship?) == true
    }
  end

  def relationship_json(relationship)
    {
      id: relationship.neat_id,
      relationship_type: relationship_type_json(relationship.relationship_type),
      parent: person_json(relationship.parent),
      child: person_json(relationship.child)
    }
  end
end
