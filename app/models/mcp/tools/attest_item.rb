# Records "this is done" on a confirmed (attested) item, as the item's "I confirm" does
# (ChecklistAttestationsController#create).
#
# Mirrors: the checklist is found as the checklists page finds it (policy_scope(Checklist)), the
# item among its attested items, the person among those the checklist covers, the attestation
# built with the item's key and statement, attested_by the viewer's person and attested_as the
# item's "who confirms" (person unless set), and authorize create? (ChecklistAttestationPolicy:
# ChecklistAttestation.may_attest?, which follows the item's setting: the person; a guardian or
# the person; or a manager of them, never for themselves or a relative; admins may always, except
# for themselves under "manager"; and not on an archived checklist). Like the page, the person is
# looked up before the check, so someone who can see the checklist can learn whether a person ID
# is covered by it. Needs the checklists feature.
class Mcp::Tools::AttestItem < Mcp::Tool
  include Mcp::ChecklistRecords

  tool_name "attest_item"
  description "Confirm a confirmed item is done for a person, as the item's I confirm does. Who may confirm is the item's setting: " \
    "the person, a guardian, or a manager; anyone else is \"Not allowed\". A checklist you can't see, or an item that isn't a confirmed item, " \
    "or a person it doesn't cover, is \"Not found\". Returns what was confirmed."
  scope :write
  feature :checklists
  input_schema(
    properties: {
      checklist_id: { type: "string", description: "The checklist's ID (chkl_)" },
      item_id: { type: "string", description: "A confirmed item on it (chli_)" },
      person_id: { type: "string", description: "The person it is confirmed for (per_), you for yourself" }
    },
    required: %w[checklist_id item_id person_id],
    closed: true
  )
  output_schema(
    type: "object",
    properties: {
      attestation_id: { type: "string" },
      item: Mcp::ChecklistRecords::ITEM_REF_SCHEMA,
      person: Mcp::Tool::REF_SCHEMA,
      statement: { type: "string" }
    },
    required: %w[attestation_id item person statement]
  )

  def call(checklist_id:, item_id:, person_id:)
    checklist = find_checklist(checklist_id)
    item = checklist.checklist_items.where(kind: "attested").then { |items| Mcp.find_by_neat_id(items, item_id) } || not_found!
    person = find_covered_person(checklist, person_id)
    attestation = ChecklistAttestation.new(person: person, key: item.config["key"], statement: item.config["statement"],
      attested_by: ctx.person, attested_as: item.config["attested_by"].presence || "person")
    attestation.item = item
    ctx.authorize!(attestation, :create?)

    invalid_argument!(attestation.errors.full_messages.to_sentence) unless attestation.save

    changed!(attestation)
    { attestation_id: attestation.neat_id, item: item_ref_json(item), person: person_json(person), statement: attestation.statement }
  end
end
