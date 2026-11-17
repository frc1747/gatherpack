# Makes an order request and sends it for approval, as New request does
# (Orders::RequestsController#create with Submit for approval).
#
# Mirrors: authorize create? on a new request for the viewer (orders_requesters), the team the
# form defaults to when none is given (the first of the viewer's teams they may ask for), and
# Orders::RequestForm with the form's own fields, which makes the draft through
# OrderRequest.draft_for and sets a funding source only through edit! (so only where
# set_funding? allows: approvers, and requesters while orders_requesters_pick_funding is on).
# Then authorize submit? and submit!, which fills a blank title from the first item and tells
# the approvers. Items are checked before anything is saved; with submit (the default) the
# draft and the submission are one step, so a refused submission leaves nothing behind.
# submit: false keeps it as a draft, as autosave does. A store is a vendor's ID, "other" with
# other_vendor_name, or "not_sure". linked_item_id links an item a line entry extension offers
# (an inventory item the viewer can see). Needs the orders feature.
class Mcp::Tools::CreateOrderRequest < Mcp::Tool
  include Mcp::OrderRecords

  LINE_PROPERTIES = {
    description: { type: "string", description: "What it is" },
    url: { type: "string", description: "Link to the product page (https)" },
    quantity: { type: "integer", minimum: 1, maximum: 1_000_000, description: "How many (default 1)" },
    store: { type: "string", description: "Where from: a vendor's ID (vnd_), \"other\" (give other_vendor_name) or \"not_sure\" (default)" },
    other_vendor_name: { type: "string", description: "The other store's name, with store \"other\"" },
    other_vendor_reason: { type: "string", description: "Why this other store, where the organization asks for one" },
    vendor_part_number: { type: "string" },
    manufacturer: { type: "string" },
    manufacturer_part_number: { type: "string" },
    unit: { type: "string", description: "each, pack, roll, ..." },
    units_per: { type: "integer", minimum: 1, maximum: 1_000_000, description: "Pieces in one unit (a pack of 100: 100)" },
    estimated_unit_price: { type: "string", description: "Price each in currency units, like \"12.50\"" },
    note: { type: "string" },
    linked_item_id: { type: "string", description: "An inventory item this is for (itm_). Optional." }
  }.freeze

  tool_name "create_order_request"
  description "Ask for things to be bought: makes an order request with one or more items and sends it for approval, as New " \
    "request does. Each item needs a link or a description. Optional: team (default your first team you may ask for), " \
    "needed_by, purpose, and a funding source where you may set one. submit: false keeps it as a draft. Returns the request."
  scope :write
  feature :orders
  input_schema(
    properties: {
      team_id: { type: "string", description: "Whose need this is (tm_). Default: your first team you may ask for." },
      needed_by: { type: "string", format: "date", description: "When it's needed (YYYY-MM-DD). Optional." },
      purpose: { type: "string", description: "What it's for; shown to approvers" },
      funding_source_id: { type: "string", description: "Paid from (fund_), where you may choose it. Optional." },
      lines: { type: "array", minItems: 1, maxItems: 50, items: { type: "object", properties: LINE_PROPERTIES, additionalProperties: false } },
      submit: { type: "boolean", description: "Send it for approval (default true); false keeps a draft" }
    },
    required: %w[lines],
    closed: true
  )
  output_schema(Mcp::OrderRecords::REQUEST_SCHEMA)

  def call(lines:, team_id: nil, needed_by: nil, purpose: nil, funding_source_id: nil, submit: true)
    team = team_id ? ctx.find(Team, team_id) : default_team
    ctx.authorize!(OrderRequest.new(requested_by: ctx.person, team: team), :create?)
    params = form_params(lines, team, needed_by, purpose, funding_source_id)

    order_request = nil
    OrderRequest.transaction do
      form = Orders::RequestForm.new(OrderRequest.new(requested_by: ctx.person, team: team), by: ctx.person, params: params)
      invalid_argument!(form.errors.to_sentence) unless form.save

      order_request = form.order_request
      # The form skips an item with nothing filled in; a request needs one.
      invalid_argument!("Add an item with a link or a description") if order_request.new_record? || order_request.order_lines.reload.none?
      if submit
        ctx.authorize!(order_request, :submit?)
        order_action { order_request.submit!(by: ctx.person) }
      end
    end
    changed!(order_request.reload, *order_request.order_lines)
    request_json(order_request)
  end

  private

  # The form's default: the first of the viewer's teams they may ask for (RequestsController#default_team).
  def default_team
    ids = Orders::Access.for(ctx.person).request_team_ids
    teams = ctx.person.teams.to_a
    teams.find { |team| ids.nil? || ids.include?(team.id) } || (ids && Team.where(id: ids.to_a).order(:name).first) ||
      invalid_argument!("Give a team_id: you aren't on a team you may ask for")
  end

  def form_params(lines, team, needed_by, purpose, funding_source_id)
    params = { "team_id" => team&.id, "purpose" => purpose, "lines" => {} }
    params["needed_by"] = parse_order_date(needed_by, "needed_by")&.iso8601 if needed_by
    params["funding_source_id"] = ctx.find(FundingSource, funding_source_id).id if funding_source_id
    lines.each_with_index { |line, index| params["lines"][index.to_s] = line_params(line.to_h.stringify_keys) }
    params
  end

  # One item as the form posts it.
  def line_params(line)
    values = line.slice(*Orders::RequestForm::LINE_FIELDS, "other_vendor_name", "estimated_unit_price").transform_values(&:to_s)
    values["quantity"] ||= "1"
    values["vendor_choice"] = vendor_choice(line["store"])
    if line["linked_item_id"].present?
      item = linked_item(line["linked_item_id"])
      values.merge!("item_type" => item.class.polymorphic_name, "item_id" => item.id)
    end
    values
  end

  def vendor_choice(store)
    case store.to_s
    when "", "not_sure" then "not_sure"
    when "other" then "other"
    else ctx.find(Vendor, store).id
    end
  end

  # A record of a type a line entry extension offers, among those the viewer can see.
  def linked_item(id)
    klass = Orders.line_item_types.filter_map(&:safe_constantize).find { |type| Mcp.find_by_neat_id(type, id) }
    klass ? ctx.find(klass, id) : not_found!
  end
end
