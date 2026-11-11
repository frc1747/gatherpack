# Copies a checklist as a draft, as ChecklistsController#copy does, taking the copy form's own
# proposals: dates shifted by shift_months (the form's 12), and each badge, team or checklist named
# with a year replaced by the one with the year shifted when one exists. The form lets a person
# change those before confirming; this takes them as proposed, and says which year-named
# references it couldn't replace (kept), so the draft can be fixed on the page. Excuses,
# attestations, results and snapshots aren't copied (Checklists::Copier).
#
# Mirrors: load_checklist (policy_scope(Checklist), authorize copy?: the checklist's organizers,
# an archived checklist too), then Checklists::Copier#call with the viewer's person as the
# copy's creator. A replacement checklist must be one the viewer can see, as the controller
# requires. The copier refuses items and grants the viewer couldn't set up themselves, with
# the page's message. A draft isn't active until someone makes it so on the page. Needs the
# checklists feature.
class Mcp::Tools::CopyChecklist < Mcp::Tool
  include Mcp::ChecklistRecords

  tool_name "copy_checklist"
  description "Copy a checklist you run as a new draft (as Copy does: dates shifted, items, rules, grants and organizers; not excuses or results), " \
    "with names that carry a year swapped for the next year's where one exists. A checklist you can't see is \"Not found\"; one you don't run is \"Not allowed\". " \
    "Returns the draft and any year-named references left unchanged (kept). Make it active on the page."
  scope :write
  feature :checklists
  input_schema(
    properties: {
      checklist_id: { type: "string", description: "The checklist to copy (chkl_)" },
      title: { type: "string", description: "The draft's title (default: the title and \"(copy)\")" },
      shift_months: { type: "integer", minimum: -1200, maximum: 1200, description: "Move fixed dates by this many months (default 12)" }
    },
    required: %w[checklist_id],
    closed: true
  )
  output_schema(
    type: "object",
    properties: {
      checklist: Mcp::ChecklistRecords::CHECKLIST_SCHEMA,
      left_out_rules: { type: "integer", description: "Rules naming something deleted, which the copy leaves out" },
      kept: { type: "array", items: { type: "string" }, description: "Names with a year that still point at the original" }
    },
    required: %w[checklist left_out_rules kept]
  )

  def call(checklist_id:, title: nil, shift_months: 12)
    checklist = find_checklist(checklist_id)
    ctx.authorize!(checklist, :copy?)

    copier = Checklists::Copier.new(checklist, shift_months: shift_months)
    replace = proposed_replacements(copier)
    kept = copier.replacements.reject { |replacement| replace.key?(replacement.key) }.map { |replacement| name_of(replacement.record) }
    copy = copy_with(copier, title, replace)

    changed!(copy)
    { checklist: checklist_json(copy), left_out_rules: copier.empty_rules.size, kept: kept }
  end

  private

  # The copy form's proposals, which the page fills in: { key => id } for each year-named record
  # that has a counterpart the viewer may use (a checklist must be one they can see).
  def proposed_replacements(copier)
    visible = ctx.policy_scope(Checklist)
    copier.replacements.select(&:proposed).reject do |replacement|
      replacement.record.is_a?(Checklist) && !visible.exists?(id: replacement.proposed.id)
    end.to_h { |replacement| [ replacement.key, replacement.proposed.id ] }
  end

  def copy_with(copier, title, replace)
    copier.call(title: title, by: ctx.person, replace: replace)
  rescue Checklists::Copier::Refused => e
    alerts = []
    alerts << "You can't copy #{e.items.to_sentence}: ask someone who can set those items up." if e.items.any?
    alerts << "You can't copy #{e.grants.to_sentence}: ask someone who can grant it." if e.grants.any?
    raise Mcp::NotAllowed, alerts.join(" ")
  rescue ActiveRecord::RecordInvalid => e
    invalid_argument!("Couldn't copy: #{e.record.errors.full_messages.to_sentence}")
  end

  def name_of(record)
    record.try(:name) || record.try(:title) || record.try(:identifier_name)
  end
end
