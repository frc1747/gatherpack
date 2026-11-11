# What the checklist tools share: a checklist as list_checklists shows it, a person's
# status on one as the report and the person's Checklists tab show it
# (Checklists::ItemStatus), and the lookups the checklist screens make.
#
# Statuses come from Checklists.status_for / Checklists::Report, which apply the
# viewer's visibility inside, so a tool can't show more than the page.
module Mcp::ChecklistRecords
  STATUSES = %w[met pending not_met exempt].freeze

  CHECKLIST_SCHEMA = {
    type: "object",
    properties: {
      id: { type: "string" },
      title: { type: "string" },
      team: Mcp::Tool::REF_SCHEMA,
      status: { type: "string", enum: %w[draft active archived] },
      starts_on: { type: %w[string null] },
      ends_on: { type: %w[string null] },
      organizer: { type: "boolean" }
    },
    required: %w[id title team status starts_on ends_on organizer]
  }.freeze

  ITEM_REF_SCHEMA = {
    type: "object",
    properties: { id: { type: "string" }, label: { type: "string" }, kind: { type: "string" } },
    required: %w[id label kind]
  }.freeze

  # A person's numbers on a count item and the credit just given or taken.
  COUNT_SCHEMA = {
    type: "object",
    properties: {
      item: ITEM_REF_SCHEMA,
      person: Mcp::Tool::REF_SCHEMA,
      credits: { type: "integer" },
      owed: { type: "integer" },
      confirmed: { type: "integer" },
      planned: { type: "integer" },
      remaining: { type: "integer" }
    },
    required: %w[item person credits owed confirmed planned remaining]
  }.freeze

  # One result: an item's (item set) or the overall's (item null). summary, detail,
  # measures, fix and excuse come only at full access. children are an any_of's items.
  CELL_SCHEMA = {
    type: "object",
    properties: {
      item: { anyOf: [ ITEM_REF_SCHEMA, { type: "null" } ] },
      status: { type: "string", enum: STATUSES },
      text: { type: "string" },
      access: { type: "string", enum: %w[full status] },
      summary: { type: %w[string null] },
      detail: { type: %w[string null] },
      measures: { type: %w[object null] },
      fix: { anyOf: [ { type: "object", properties: { label: { type: "string" }, action: { type: %w[string null] }, path: { type: %w[string null] } } }, { type: "null" } ] },
      excuse: {
        anyOf: [
          { type: "object", properties: { excused: { type: "boolean" }, excuse_id: { type: "string" }, by: { type: %w[string null] }, at: { type: "string" },
                                          expires_on: { type: %w[string null] }, reason: { type: "string" } } },
          { type: "null" }
        ]
      },
      children: { type: "array", items: { type: "object" } }
    },
    required: %w[item status text access]
  }.freeze

  private

  def checklist_json(checklist)
    window = checklist.window
    {
      id: checklist.neat_id,
      title: checklist.title,
      team: team_json(checklist.team),
      status: checklist.status,
      starts_on: date_json(window.starts_on),
      ends_on: date_json(window.ends_on),
      organizer: checklist.organizer?(ctx.person)
    }
  end

  # The checklist as the checklists page finds it: policy_scope(Checklist), so one the
  # viewer can't see is "Not found" (a draft is for those who run it).
  def find_checklist(neat_id)
    ctx.find(Checklist, neat_id)
  end

  # An item of the checklist, as the screens find it (checklist.checklist_items.find).
  def find_item(checklist, neat_id)
    Mcp.find_by_neat_id(checklist.checklist_items, neat_id) || not_found!
  end

  # Someone the checklist covers (Checklists.people_covered_by, as the excuse and
  # attestation screens look people up).
  def find_covered_person(checklist, neat_id)
    Mcp.find_by_neat_id(Checklists.people_covered_by(checklist), neat_id) || not_found!
  end

  # The person's group's numbers on a count item, fresh from its commitment (what the stored
  # result catches up to when the checklist refreshes).
  def count_json(item, commitment, person)
    progress = Commitment.find(commitment.id).progress_for(person)
    { item: item_ref_json(item), person: person_json(person), owed: progress.owed, confirmed: progress.confirmed,
      planned: progress.planned, remaining: progress.remaining }
  end

  def item_ref_json(item)
    { id: item.neat_id, label: item.label, kind: item.kind }
  end

  def cell_json(entry)
    json = { item: entry.item && item_ref_json(entry.item), status: entry.status, text: entry.text, access: entry.access.to_s }
    if entry.full?
      json.merge!(summary: entry.summary, detail: entry.detail, measures: entry.measures, fix: fix_json(entry.fix))
    end
    json[:excuse] = excuse_json(entry.excuse) if entry.excuse
    json[:children] = entry.children.map { |child| cell_json(child) } if entry.children.present?
    json
  end

  def fix_json(fix)
    fix.present? ? { label: fix["label"], action: fix["action"], path: fix["path"] } : nil
  end

  # What Checklists::Reader gives: just "excused" below full access; by and when, and the
  # reason for managers, otherwise.
  def excuse_json(excuse)
    return { excused: true } if excuse["excused"]

    json = { excused: true, by: excuse["by"], at: excuse["at"], expires_on: excuse["expires_on"] }
    json[:excuse_id] = ChecklistExcuse.new(id: excuse["id"]).neat_id if excuse["id"]
    json[:reason] = excuse["reason"] if excuse["reason"]
    json
  end

  def status_json(status)
    { overall: status.overall && cell_json(status.overall), items: status.items.map { |entry| cell_json(entry) } }
  end

  # The refusal a screen gives when someone who runs a thing may not do it to this
  # person, named as the app names it; plain "Not allowed" for anyone else.
  def refuse!(reason = nil)
    raise Mcp::NotAllowed, "Not allowed: #{reason}" if reason

    raise Mcp::NotAllowed
  end
end
