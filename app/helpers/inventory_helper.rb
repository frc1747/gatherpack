require "rqrcode"

# Screen words and small pieces shared by the inventory pages (spec §3.9).
module InventoryHelper
  KIND_LABELS = {
    "used" => "Used", "moved" => "Moved", "counted" => "Counted",
    "received" => "Received", "added" => "Added", "removed" => "Removed"
  }.freeze

  # What each form asks for its place, and its main button.
  KIND_FORMS = {
    "used" => { place: "From", action: "Done" },
    "moved" => { place: "From", action: "Move" },
    "counted" => { place: "Place", action: "Save count" },
    "received" => { place: "Into", action: "Record received" },
    "added" => { place: "Into", action: "Record added" },
    "removed" => { place: "From", action: "Record removed" }
  }.freeze

  def inventory_kind_label(kind)
    KIND_LABELS.fetch(kind.to_s, kind.to_s.humanize)
  end

  def inventory_stylesheet
    content_for :head, stylesheet_link_tag("inventory")
  end

  # "14", or "14 feet" when the item isn't counted in each.
  def inventory_quantity(quantity, item)
    item.stock_unit ? item.stock_unit.quantity_text(quantity) : quantity.to_s
  end

  # Running low, Out of stock and Needs a count, as badges.
  def inventory_stock_badges(item, total: nil, needs_count: false)
    total ||= item.total_stock
    badges = []
    if item.out_of_stock?(total) && !item.reorder_point.nil?
      badges << tag.span("Out of stock", class: "badge text-bg-danger")
    elsif item.low?(total)
      badges << tag.span("Running low", class: "badge text-bg-warning")
    end
    badges << tag.span("Needs a count", class: "badge text-bg-secondary") if needs_count
    badges << tag.span("Inactive", class: "badge text-bg-light border") unless item.active?
    safe_join(badges, " ")
  end

  # "Build shop › Cabinet A › Bin 3" from places already loaded, without a
  # query per ancestor. places is { id => Location }.
  def inventory_place_name(location, places)
    names = []
    current = location
    seen = Set.new
    while current && seen.add?(current.id)
      names.unshift(current.name)
      current = current.parent_id && (places[current.parent_id] || current.parent)
    end
    names.join(" › ")
  end

  # May the person record this kind of change for the item at the place.
  def inventory_may_record?(kind, item, location)
    return false if location.nil? || item.tracked? || !item.active?

    Inventory::Access.for(current_person).may_record?(kind, item, location)
  end

  # One line of history: a move's two rows read as one.
  def inventory_change_text(movement, partner: nil)
    item = movement.item
    quantity = inventory_quantity(movement.quantity.abs, item)
    text =
      case movement.kind
      when "moved"
        from, to = movement.quantity.negative? ? [ movement.location, partner&.location ] : [ partner&.location, movement.location ]
        "Moved #{quantity} from #{from&.name || "?"} to #{to&.name || "?"}"
      when "counted"
        if movement.reversal?
          "Count undone at #{movement.location.name}"
        else
          difference = movement.quantity.zero? ? "matched" : format("%+d", movement.quantity)
          "Counted #{movement.counted_quantity} at #{movement.location.name} (#{difference})"
        end
      when "used", "removed"
        "#{inventory_kind_label(movement.kind)} #{quantity} from #{movement.location.name}"
      else
        "#{inventory_kind_label(movement.kind)} #{quantity} into #{movement.location.name}"
      end
    text = "Undo: #{text}" if movement.reversal? && movement.kind != "counted"
    text
  end

  ORDER_REQUEST_NOTE = %r{Order request: (?<title>.*?) \((?<path>/orders/requests/[^\s)]+)\)}
  NOTE_LINK = %r{https?://\S+|/orders/requests/[^\s)]+}

  # A change's note as text, with an order request or web address in it as a
  # short link ("Order request: Title (/orders/requests/...)" becomes a link
  # named by the title) rather than the address itself.
  def inventory_note(note)
    return "".html_safe if note.blank?

    note = note.to_s
    if (match = ORDER_REQUEST_NOTE.match(note))
      return safe_join([ match.pre_match, link_to(match[:title].presence || "Order request", match[:path]), match.post_match ])
    end

    parts = note.split(/(#{NOTE_LINK})/o)
    safe_join(parts.map do |part|
      next part unless part.match?(/\A#{NOTE_LINK}\z/o)

      link_to(part.start_with?("/orders/") ? "Order request" : "Link", part, target: ("_blank" unless part.start_with?("/")), rel: "noopener")
    end)
  end

  # Who did it, and who entered it when that was someone else.
  def inventory_change_who(movement)
    who = movement.person&.identifier_name || "Someone no longer here"
    movement.recorded_by ? "#{who} (entered by #{movement.recorded_by.identifier_name})" : who
  end

  # The change just recorded on the previous page, once, when the person
  # can still undo it.
  def inventory_pending_undo
    id = session.delete(:inventory_undo)
    return if id.nil?

    movement = StockMovement.find_by(id: id)
    movement if movement&.undoable_by?(current_person)
  end

  # The unit action just taken on the previous page, once: { text:, event: },
  # with event nil when the person can no longer undo it.
  def inventory_pending_unit_undo(unit)
    pending = session.delete(:inventory_unit_undo)
    return if pending.nil?

    event = unit.events.find_by(id: pending["id"])
    { text: pending["text"], event: (event if event && policy(event).undo?) }
  end

  # A count that changed stock by more than a fifth.
  def inventory_big_count?(movement)
    return false unless movement.counted? && !movement.reversal?

    before = movement.counted_quantity.to_i - movement.quantity
    before.zero? ? !movement.quantity.zero? : movement.quantity.abs > before.abs * 0.2
  end

  # A QR code of the URL as inline SVG.
  def inventory_qr_code(url)
    RQRCode::QRCode.new(url).as_svg(module_size: 3, use_path: true, viewbox: true,
      svg_attributes: { class: "inventory-qr", role: "img", "aria-label": "QR code" }).sub(/\A<\?xml[^>]*\?>/, "").html_safe
  end
end
