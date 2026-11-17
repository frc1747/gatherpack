# What the orders tools share: a request, an item, a purchase and a funding source as the
# orders pages show them to the viewer, and the lookups those pages make.
#
# Requests are found through policy_scope(OrderRequest) and asked show?, as
# Orders::RequestsController does. Words and what a viewer may see come from the pages'
# own helpers (Mcp::OrderWords): the shown total leaves out estimated shipping for those
# who don't see it, the timeline leaves out funding changes for those who don't see
# funding, and a purchase seen only through a request gives its vendor, dates and status.
#
# A domain action's Orders::Refused comes back as an invalid-argument error with the
# page's message; a validation error the same way. A refusal by policy is "Not allowed".
module Mcp::OrderRecords
  REQUEST_STATUSES = %w[draft submitted changes_requested approved ordering received closed declined cancelled].freeze
  LINE_STATUSES = %w[pending approved ordered backordered partly_received received problem cancelled needs_reapproval].freeze

  MONEY_SCHEMA = {
    type: "object",
    properties: { cents: { type: "integer" }, formatted: { type: "string" } },
    required: %w[cents formatted]
  }.freeze
  NULLABLE_MONEY = { anyOf: [ MONEY_SCHEMA, { type: "null" } ] }.freeze
  NULLABLE_REF = { anyOf: [ Mcp::Tool::REF_SCHEMA, { type: "null" } ] }.freeze

  REQUEST_REF_SCHEMA = {
    type: "object",
    properties: { id: { type: "string" }, title: { type: "string" } },
    required: %w[id title]
  }.freeze

  # A request as the request lists show it.
  REQUEST_SCHEMA = {
    type: "object",
    properties: {
      id: { type: "string" },
      title: { type: "string" },
      status: { type: "string", enum: REQUEST_STATUSES },
      status_text: { type: "string" },
      team: Mcp::Tool::REF_SCHEMA,
      requested_by: Mcp::Tool::REF_SCHEMA,
      needed_by: { type: %w[string null] },
      total: MONEY_SCHEMA,
      items: { type: "integer" },
      updated_at: { type: "string" }
    },
    required: %w[id title status status_text team requested_by needed_by total items updated_at]
  }.freeze

  # An item on a request, as the request page shows it.
  LINE_SCHEMA = {
    type: "object",
    properties: {
      id: { type: "string" },
      description: { type: "string" },
      status: { type: "string", enum: LINE_STATUSES },
      status_text: { type: "string" },
      quantity: { type: "integer" },
      unit: { type: %w[string null] },
      units_per: { type: %w[integer null] },
      store: { type: "string" },
      vendor: NULLABLE_REF,
      vendor_part_number: { type: %w[string null] },
      manufacturer: { type: %w[string null] },
      manufacturer_part_number: { type: %w[string null] },
      unit_price: NULLABLE_MONEY,
      url: { type: %w[string null] },
      note: { type: %w[string null] },
      expected_on: { type: %w[string null] },
      funding_source: NULLABLE_REF,
      linked_item: {
        anyOf: [
          { type: "object", properties: { type: { type: "string" }, id: { type: %w[string null] }, name: { type: "string" } } },
          { type: "null" }
        ]
      }
    },
    required: %w[id description status status_text quantity store unit_price]
  }.freeze

  FUNDING_SOURCE_SCHEMA = {
    type: "object",
    properties: {
      id: { type: "string" },
      name: { type: "string" },
      team: Mcp::Tool::REF_SCHEMA,
      kind: { type: "string", enum: %w[general restricted] },
      active: { type: "boolean" },
      starts_on: { type: %w[string null] },
      ends_on: { type: %w[string null] },
      restriction: { type: %w[string null] },
      numbers: {
        anyOf: [
          {
            type: "object",
            properties: { amount: NULLABLE_MONEY, spent: MONEY_SCHEMA, committed: MONEY_SCHEMA, remaining: NULLABLE_MONEY,
                          spent_outside: NULLABLE_MONEY, spent_outside_as_of: { type: %w[string null] } },
            required: %w[amount spent committed remaining]
          },
          { type: "null" }
        ]
      },
      giver: { type: %w[string null] },
      reference: { type: %w[string null] },
      report_due_on: { type: %w[string null] }
    },
    required: %w[id name team kind active numbers]
  }.freeze

  PURCHASE_SCHEMA = {
    type: "object",
    properties: {
      id: { type: "string" },
      vendor_name: { type: %w[string null] },
      ordered_on: { type: %w[string null] },
      expected_on: { type: %w[string null] },
      status_text: { type: "string" },
      full: { type: "boolean" },
      items: { type: "integer" },
      vendor_order_number: { type: %w[string null] },
      buyer: NULLABLE_REF,
      total: NULLABLE_MONEY
    },
    required: %w[id vendor_name ordered_on expected_on status_text full items]
  }.freeze

  private

  def order_words
    @order_words ||= Mcp::OrderWords.new(ctx.user)
  end

  # The request with this ID the viewer may see, as the request page finds it.
  def find_order_request(id)
    order_request = ctx.find(OrderRequest, id)
    ctx.authorize!(order_request, :show?)
    order_request
  end

  # An item on a request the viewer may see.
  def find_order_line(id)
    ctx.find(OrderLine.where(order_request_id: ctx.policy_scope(OrderRequest).select(:id)), id)
  end

  # Runs a domain action, giving back its refusal or validation error as the page's message.
  def order_action
    yield
  rescue Orders::Refused => e
    invalid_argument!(e.message)
  rescue ActiveRecord::RecordInvalid => e
    invalid_argument!(e.record.errors.full_messages.to_sentence)
  end

  def parse_order_date(value, name)
    Date.iso8601(value) if value.present?
  rescue Date::Error
    invalid_argument!("#{name} must be a date, YYYY-MM-DD")
  end

  def request_ref_json(order_request)
    { id: order_request.neat_id, title: order_request.display_title }
  end

  def request_json(order_request)
    {
      id: order_request.neat_id,
      title: order_request.display_title,
      status: order_request.status,
      status_text: order_words.order_request_status_text(order_request),
      team: team_json(order_request.team),
      requested_by: person_json(order_request.requested_by),
      needed_by: date_json(order_request.needed_by),
      total: money_json(order_words.order_request_shown_total(order_request)),
      items: order_request.live_lines.size,
      updated_at: time_json(order_request.updated_at)
    }
  end

  def line_json(line, see_funding: order_words.policy(line.order_request).see_funding?)
    {
      id: line.neat_id,
      description: line.display_name,
      status: line.status,
      status_text: order_words.order_line_status_text(line),
      quantity: line.quantity,
      unit: line.unit.presence,
      units_per: line.units_per,
      store: store_text(line),
      vendor: line.vendor && { id: line.vendor.neat_id, name: line.vendor.name },
      vendor_part_number: line.vendor_part_number.presence,
      manufacturer: line.manufacturer.presence,
      manufacturer_part_number: line.manufacturer_part_number.presence,
      unit_price: money_json(line.unit_price_cents),
      url: line.url.presence,
      note: line.note.presence,
      expected_on: (date_json(line.expected_on) if line.backordered?),
      funding_source: (funding_ref_json(line.funding_source) if see_funding && line.funding_source),
      linked_item: linked_item_json(line.item)
    }
  end

  # Where from, in the request page's words.
  def store_text(line)
    case line.vendor_choice
    when :vendor then line.vendor.name
    when :other then "Other store: #{line.other_vendor_name}"
    else "Store not chosen"
    end
  end

  # The record a line was made from (an inventory item), by name, as the page links it.
  def linked_item_json(item)
    return nil if item.nil?

    { type: item.class.name, id: item.try(:neat_id), name: (item.try(:identifier_name) || item.try(:name) || item.model_name.human).to_s }
  end

  def funding_ref_json(source)
    { id: source.neat_id, name: source.name }
  end

  def funding_source_json(source)
    policy = order_words.policy(source)
    json = {
      id: source.neat_id,
      name: source.name,
      team: team_json(source.team),
      kind: source.kind,
      active: source.active?,
      starts_on: date_json(source.starts_on),
      ends_on: date_json(source.ends_on),
      restriction: (source.restriction if source.restricted?),
      numbers: (funding_numbers_json(source) if policy.numbers?)
    }
    if policy.restricted_fields? && source.restricted?
      json.merge!(giver: source.giver.presence, reference: source.reference.presence, report_due_on: date_json(source.report_due_on))
    end
    json
  end

  def funding_numbers_json(source)
    {
      amount: money_json(source.amount_cents),
      spent: money_json(source.spent_cents),
      committed: money_json(source.committed_cents),
      remaining: money_json(source.remaining_cents),
      spent_outside: (money_json(source.spent_outside_cents) if source.spent_outside_cents.to_i.positive?),
      spent_outside_as_of: (date_json(source.spent_outside_as_of) if source.spent_outside_cents.to_i.positive?)
    }
  end

  # A purchase as the purchase list shows it: the whole of it to those who see it all,
  # otherwise the vendor, dates and the status of their own items.
  def purchase_json(purchase)
    policy = order_words.policy(purchase)
    full = policy.full?
    lines = policy.visible_lines
    {
      id: purchase.neat_id,
      vendor_name: purchase.vendor_name,
      ordered_on: date_json(purchase.ordered_on),
      expected_on: date_json(purchase.expected_on),
      status_text: order_words.purchase_status_text(lines),
      full: full,
      items: lines.size,
      vendor_order_number: (purchase.vendor_order_number.presence if full),
      buyer: (person_json(purchase.buyer) if full),
      total: (money_json(purchase.total_cents) if full)
    }
  end
end
