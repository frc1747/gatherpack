# Adds a relationship between two people, as RelationshipsController#create does.
#
# That controller inherits ApplicationController, so no verify_* runs, and RelationshipPolicy#create?
# is plain true. The real rule is the model's: create (lines 9-12) sets created_by to the viewer,
# whom Relationship#permission_check (line 52) compares with the two people for the type's
# permission. That failure, which the page shows as an error on both people, is "Not allowed";
# other validations (a person related to themselves) are invalid-argument errors. Nothing stops
# a duplicate, on the page or here. The form's start_node only picks the type and which side the
# profile's person is on, and this takes both sides directly, so reify isn't needed.
#
# Both people are looked up in policy_scope(Person). The form picks the other person from that scope
# ("people" combobox, new lines 17 and 24) and is reached from a profile in it, while the POST looks up
# no one's permission (Person.find, line 44, and the permitted parent_id and child_id). The result names
# both, so this keeps to the form's list. The type isn't scoped: the model decides.
class Mcp::Tools::AddRelationship < Mcp::Tool
  include Mcp::RelationshipRecords

  tool_name "add_relationship"
  description "Record a relationship between two people, as Add Relationship does on a person's Relationships page. " \
    "A relationship type you may not add between these people is \"Not allowed\"; someone you can't see is \"Not found\". Returns it with both people."
  scope :write
  input_schema(
    properties: {
      parent_id: { type: "string", description: "The person on the parent side (per_)" },
      child_id: { type: "string", description: "The person on the child side (per_)" },
      relationship_type_id: { type: "string", description: "The type's ID (rety_), from list_relationship_types" }
    },
    required: %w[parent_id child_id relationship_type_id]
  )
  output_schema(Mcp::RelationshipRecords::SCHEMA)

  def call(parent_id:, child_id:, relationship_type_id:)
    relationship = Relationship.new(
      parent: ctx.find(Person, parent_id),
      child: ctx.find(Person, child_id),
      relationship_type: ctx.find(RelationshipType.all, relationship_type_id),
      created_by: ctx.person
    )
    ctx.authorize!(relationship, :create?)
    save!(relationship)

    changed!(relationship)
    relationship_json(relationship)
  end

  private

  def save!(relationship)
    return if relationship.save
    raise Mcp::NotAllowed if relationship.errors.added?(:parent, "does not meet relationship requirements")

    invalid_argument!(relationship.errors.full_messages.to_sentence)
  end
end
