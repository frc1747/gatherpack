# A ledger's entries, newest first, as the ledger page lists them. The ledger
# comes from policy_scope(Ledger) (LedgersController#set_ledger) and entries
# from policy_scope on its entries (LedgerEntriesController#set_ledger_entry);
# the ledger page itself lists every entry of a visible ledger, so the tool is
# no wider. Needs the ledger feature. from and to filter on the posting date
# (created_at, inclusive, in the app's time zone) and are optional but must be
# valid dates; tag matches a tag's name, ignoring case. Receipts, metadata and
# who posted an entry are left out. status is "final", "pending" (not
# finalized) or "failed"; split_parent is the ID of the entry a split row
# belongs to.
class Mcp::Tools::LedgerEntries < Mcp::Tool
  tool_name "ledger_entries"
  description "Entries of one ledger you can see, newest first, with date, description, amount, tags, status and the " \
    "entry they were split from. Optionally only a date range (YYYY-MM-DD, inclusive) or one tag name."
  scope :read
  feature :ledger
  input_schema(
    properties: {
      ledger_id: { type: "string", description: "The ledger's ID (leg_)" },
      from: { type: "string", description: "First day posted, YYYY-MM-DD" },
      to: { type: "string", description: "Last day posted, YYYY-MM-DD" },
      tag: { type: "string", description: "Only entries with this tag (name)" },
      limit: limit_property
    },
    required: [ "ledger_id" ]
  )
  output_schema(
    type: "object",
    properties: {
      items: {
        type: "array",
        items: {
          type: "object",
          properties: {
            id: { type: "string" },
            date: { type: "string" },
            description: { type: [ "string", "null" ] },
            amount: { type: "object", properties: { cents: { type: "integer" }, formatted: { type: "string" } }, required: %w[cents formatted] },
            tags: { type: "array", items: { type: "string" } },
            status: { type: "string", enum: %w[final pending failed] },
            split_parent: { type: [ "string", "null" ] }
          },
          required: %w[id date description amount tags status split_parent]
        }
      },
      truncated: { type: "boolean" }
    },
    required: %w[items truncated]
  )

  def call(ledger_id:, from: nil, to: nil, tag: nil, limit: DEFAULT_LIMIT)
    first = from && parse_date(from, "from")
    last = to && parse_date(to, "to")
    invalid_argument!("to can't be before from") if first && last && last < first

    ledger = ctx.find(Ledger, ledger_id)
    entries = ctx.policy_scope(ledger.ledger_entries)
    entries = entries.where(created_at: first.in_time_zone.beginning_of_day..) if first
    entries = entries.where(created_at: ..last.in_time_zone.end_of_day) if last
    entries = entries.where(id: LedgerTagging.joins(:ledger_tag).where("LOWER(ledger_tags.name) = ?", tag.strip.downcase).select(:ledger_entry_id)) if tag

    list(entries.includes(:ledger_tags, :parent).order(created_at: :desc, id: :desc), limit: limit) do |entry|
      {
        id: entry.neat_id,
        date: date_json(entry.created_at),
        description: entry.remark.presence,
        amount: money_json(entry.amount),
        tags: entry.ledger_tags.map(&:name).compact.sort,
        status: status(entry),
        split_parent: entry.parent&.neat_id
      }
    end
  end

  private

  def status(entry)
    if entry.failed then "failed"
    elsif entry.finalized then "final"
    else "pending"
    end
  end

  def parse_date(value, name)
    Date.iso8601(value)
  rescue Date::Error
    invalid_argument!("#{name} must be a date like 2026-03-31")
  end
end
