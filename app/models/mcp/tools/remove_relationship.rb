# Removes a relationship, as RelationshipsController#destroy does (lines 37-38):
# Relationship.find, authorize destroy?, destroy. RelationshipPolicy#destroy? is admins and the two
# people in it, so a team's manager can't, on the page or here. The controller inherits
# ApplicationController, so no verify_* runs, and the profile in the URL decides nothing.
#
# Someone destroy? refuses gets "Not allowed" if the relationship is in
# policy_scope(Relationship) and "Not found" otherwise. destroy? is asked first because a build's
# may allow someone that scope leaves out.
class Mcp::Tools::RemoveRelationship < Mcp::Tool
  include Mcp::RelationshipRecords

  tool_name "remove_relationship"
  description "Remove a relationship, as Delete does on a person's Relationships page. One you can see but not remove is \"Not allowed\". Returns what was removed."
  scope :write
  destructive
  input_schema(
    properties: { relationship_id: { type: "string", description: "The relationship's ID (rel_)" } },
    required: %w[relationship_id]
  )
  output_schema(Mcp::RelationshipRecords::SCHEMA.merge(
    properties: Mcp::RelationshipRecords::SCHEMA[:properties].merge(removed: { type: "boolean" }),
    required: Mcp::RelationshipRecords::SCHEMA[:required] + %w[removed]
  ))

  def call(relationship_id:)
    relationship = ctx.find(Relationship.all, relationship_id)
    not_found! unless ctx.allowed?(relationship, :destroy?) || ctx.policy_scope(Relationship).exists?(id: relationship.id)
    ctx.authorize!(relationship, :destroy?)
    invalid_argument!(relationship.errors.full_messages.to_sentence) unless relationship.destroy

    changed!(relationship)
    relationship_json(relationship).merge(removed: true)
  end
end
