# The requester's screens (spec §3.16): the request form's choices and the
# timeline's wording. Screen words follow OrdersHelper.
module OrderRequestsHelper
  TIMELINE_WORDS = {
    "submitted" => "Sent for approval",
    "edited" => "Changed",
    "approved" => "Approved",
    "changes_requested" => "Asked for changes",
    "declined" => "Declined",
    "purchased" => "Ordered",
    "backordered" => "Delayed",
    "received" => "Received",
    "problem" => "Problem with delivery",
    "cancelled" => "Cancelled",
    "commented" => "Commented",
    "reapproval_needed" => "Needs re-approval",
    "closed" => "Closed"
  }.freeze

  # Following and unfollowing show in the Following list, not the timeline.
  TIMELINE_HIDDEN = %w[followed unfollowed].freeze

  FIELD_WORDS = {
    "status" => "Status", "title" => "Title", "purpose" => "What it's for", "needed_by" => "Needed by",
    "team_id" => "Team", "funding_source_id" => "Funding source", "funding_source" => "Funding source",
    "estimated_shipping_cents" => "Estimated shipping", "description" => "What it is", "url" => "Link",
    "quantity" => "How many", "vendor_id" => "Store", "other_vendor_name" => "Other store",
    "other_vendor_reason" => "Why this store", "vendor_part_number" => "Store part number",
    "manufacturer" => "Maker", "manufacturer_part_number" => "Maker part number", "unit" => "Unit",
    "units_per" => "Pieces per unit", "estimated_unit_price_cents" => "Price each",
    "actual_unit_price_cents" => "Price paid each", "note" => "Note", "expected_on" => "Expected",
    "photo" => "Photo", "added" => "Added item", "total" => "Total", "lines" => "Items",
    "condition" => "Condition", "item_id" => "Item from the list", "resolution" => "Resolved by", "reordered" => "Reordered"
  }.freeze

  FUNDING_FIELDS = %w[funding_source_id funding_source line_funding_source_ids].freeze
  MONEY_FIELDS = %w[estimated_shipping_cents estimated_unit_price_cents actual_unit_price_cents].freeze

  # Active vendors for the link box and the Where from? list, preferred
  # first, plus the line's own vendor if it's no longer active.
  def order_vendors(lines = [])
    vendors = Vendor.active.listed.to_a
    extra = lines.filter_map { |line| line.vendor if line.vendor && !line.vendor.active? }
    vendors + extra.uniq
  end

  # What the link box needs to know: no account notes.
  def order_vendors_json(vendors)
    vendors.select(&:active?).map do |vendor|
      { id: vendor.id, name: vendor.name, domains: Array(vendor.domains), pattern: vendor.part_number_pattern.presence }
    end.to_json
  end

  def order_line_vendor_choice(line)
    case line.vendor_choice
    when :vendor then line.vendor_id
    when :other then "other"
    else "not_sure"
    end
  end

  def order_vendor_options(vendors, line)
    options = vendors.map { |vendor| [ vendor.name, vendor.id ] } + [ [ "Other store", "other" ], [ "Not sure", "not_sure" ] ]
    options_for_select(options, order_line_vendor_choice(line))
  end

  # The teams the person may ask for, when there's a choice.
  def order_request_team_options(person)
    access = Orders::Access.for(person)
    ids = access.request_team_ids
    teams = ids.nil? ? Team.order(:name) : Team.where(id: ids.to_a).order(:name)
    teams.to_a
  end

  # The next event on each team's calendar, for the "Before [event]" pick:
  # { team id => { date:, label: } }. Needed by the day before it, or today.
  def order_next_events(teams)
    events = Event.where(team_id: teams.map(&:id)).where(start_time: Time.current..).order(:start_time)
    events.each_with_object({}) do |event, picks|
      next if picks.key?(event.team_id)

      date = [ event.start_time.to_date - 1, Date.current ].max
      picks[event.team_id] = { date: date.iso8601, label: "Before #{event.name.presence || 'the next event'}" }
    end
  end

  # The needed-by quick picks (spec §3.16), each { label:, value:,
  # checked:, kind:, hidden: }. "pick" shows the date box and "" is No
  # rush. The event pick is always there, hidden while the team has no
  # event coming up, so the form can show it when the team changes.
  def order_needed_by_picks(needed_by, event_pick)
    today = Date.current
    picks = [
      { label: "ASAP", value: today.iso8601 },
      { label: "This week", value: today.end_of_week.iso8601 },
      { label: event_pick&.dig(:label).to_s, value: event_pick&.dig(:date).to_s, kind: :event, hidden: event_pick.nil? },
      { label: "Pick a date", value: "pick" },
      { label: "No rush", value: "" }
    ]
    current = needed_by&.iso8601
    checked = picks.find { |pick| !pick[:hidden] && current && pick[:value] == current }
    checked ||= picks.find { |pick| !pick[:hidden] && pick[:value] == (current ? "pick" : "") }
    checked[:checked] = true
    picks
  end

  # The total a viewer may see: without estimated shipping for those who
  # don't see it (spec §3.16).
  def order_request_shown_total(order_request)
    if policy(order_request).see_estimated_shipping?
      order_request.total
    else
      Money.new(order_request.live_lines.sum(&:cost_cents))
    end
  end

  # The line's link, or its text when it isn't a web link (so a stored
  # javascript: or data: URL is never clickable).
  def order_line_link(line)
    return line.url unless line.web_link?

    link_to line.url, line.url, target: "_blank", rel: "noopener noreferrer"
  end

  # A small copy of the line's photo, so a phone doesn't download camera
  # originals. A photo that can't be resized is linked instead.
  def order_line_photo_thumbnail(line)
    photo = line.photo
    return link_to("Photo of #{line.display_name}", rails_blob_path(photo), target: "_blank", rel: "noopener") unless photo.variable?

    image_tag photo.variant(resize_to_limit: [ 400, 400 ]), class: "orders-line-photo", alt: "Photo of #{line.display_name}"
  end

  # Funding sources the form offers: active ones the team can use, plus the
  # request's current one even if it no longer is, so saving the form
  # doesn't clear it.
  def order_funding_source_options(order_request)
    sources = FundingSource.active.order(:name).select { |source| order_request.team.nil? || source.usable_by?(order_request.team) }
    sources.unshift(order_request.funding_source) if order_request.funding_source && sources.exclude?(order_request.funding_source)
    sources.map { |source| [ source.name, source.id ] }
  end

  # The record a line was made from (an inventory item, say): its name,
  # linked when it has a page.
  def order_line_item_link(item)
    name = item.try(:identifier_name) || item.try(:name) || item.model_name.human
    link_to name, polymorphic_path(item)
  rescue NoMethodError, ActionController::UrlGenerationError
    name
  end

  def order_timeline_events(order_request)
    order_request.events.includes(:actor, :order_line).reject { |event| event.action.in?(TIMELINE_HIDDEN) }
  end

  # "Approved (Mentor)", "Sent back for approval", ...
  def order_timeline_action(event)
    words = TIMELINE_WORDS.fetch(event.action, event.action.humanize)
    words = "Sent back for approval" if event.action == "submitted" && event.field_changes&.dig("status", 0) == "changes_requested"
    words += " (#{event.step_name})" if event.step_key.present?
    words
  end

  # The changed fields as "Label: before → after" lines, leaving out what
  # this viewer doesn't see.
  def order_timeline_changes(event, order_request)
    changes = event.field_changes.to_h
    changes = changes.except(*FUNDING_FIELDS) unless policy(order_request).see_funding?
    changes = changes.except("estimated_shipping_cents") unless policy(order_request).see_estimated_shipping?
    changes = changes.except("item_type")
    changes.filter_map do |field, value|
      next "Approvals need to be given again" if field == "approvals_cleared"
      next "Funding source cleared on #{pluralize(value.size, 'item')}" if field == "line_funding_source_ids"

      label = FIELD_WORDS.fetch(field, field.humanize)
      if value.is_a?(Array) && value.size == 2 && field != "lines"
        "#{label}: #{order_timeline_value(field, value[0], event)} → #{order_timeline_value(field, value[1], event)}"
      else
        "#{label}: #{order_timeline_value(field, value, event)}"
      end
    end
  end

  def order_timeline_value(field, value, event)
    return "none" if value.blank?

    case field
    when "status"
      words = event.order_line_id ? OrdersHelper::LINE_STATUS_WORDS : OrdersHelper::REQUEST_STATUS_WORDS
      words.fetch(value.to_s, value.to_s.humanize)
    when *MONEY_FIELDS then Money.new(value).format
    when "vendor_id" then order_timeline_name(Vendor, value)
    when "team_id" then order_timeline_name(Team, value)
    when "funding_source_id" then order_timeline_name(FundingSource, value)
    when "needed_by", "expected_on" then l(Date.parse(value.to_s), format: :long)
    when "lines" then Array(value).to_sentence
    when "condition" then order_timeline_condition(value)
    when "item_id" then "linked"
    else value.to_s
    end
  rescue Date::Error
    value.to_s
  end

  private

  # How a delivery came: "Good", or the problem kind's current name. Kinds
  # are logged by key when they have one ("damaged"), else by id.
  def order_timeline_condition(value)
    value = value.to_s
    return "Good" if value == "good"

    @order_timeline_names ||= {}
    @order_timeline_names[[ DeliveryProblemKind, value ]] ||=
      DeliveryProblemKind.find_by(key: value)&.name ||
      (DeliveryProblemKind.find_by(id: value)&.name if value.match?(/\A\h{8}-\h{4}-\h{4}-\h{4}-\h{12}\z/)) ||
      value.humanize
  end

  def order_timeline_name(klass, id)
    @order_timeline_names ||= {}
    @order_timeline_names[[ klass, id ]] ||= klass.find_by(id: id)&.name || "removed"
  end
end
