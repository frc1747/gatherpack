# Order receiving into inventory (orders spec §5, inventory spec §5): the
# only code that knows both orders and inventory. It plugs into their seams
# (config/initializers/order_inventory.rb) and is on while both features
# are on.
#
# - Pick from what we stock: a line entry extension that fills an item on
#   the request form from an Item and links it.
# - Put away: a receiving extension that records a delivery as received
#   stock (quantity × units_per), or as units for a tracked item.
# - Order these: a reorder action that starts a draft with OrderRequest.draft_for.
# - On order: open, bought lines that carry an item count as on order.
module OrderInventory
  # Line statuses that are bought and still on their way.
  ON_ORDER_STATUSES = %w[ordered backordered partly_received problem].freeze

  def self.enabled?
    Orders.enabled? && Inventory.enabled?
  end

  # Registers the bridge in the seams of both features. Registering again
  # replaces the earlier entries, so it's safe to call more than once.
  def self.register!
    ItemSource.include(OrderInventory::ItemSourceVendor)

    # Pick from what we stock, above the items on New request.
    Orders.line_entry_extensions.register(:order_inventory, partial: "order_inventory/line_picker",
      item_types: [ "Item" ], attributes: ->(item) { line_attributes(item) })

    # Put away in a place, or as units for a tracked item.
    Orders.receiving_extensions.register(:order_inventory, partial: "order_inventory/receive_fields",
      after_receive: ->(delivery, params) { OrderInventory::PutAway.call(delivery, params) })

    # Bought lines still to come keep their items off the reorder list.
    Inventory.extensions.register_on_order(method(:on_order))

    # Order these: the reorder list runs it (a POST) and goes to a page to
    # check the items; only that page's own POST makes the draft.
    routes = Rails.application.routes.url_helpers
    Inventory.extensions.register_reorder_action(:order_these, label: "Order these",
      path: ->(rows) { routes.new_order_inventory_reorder_draft_path(items: rows.to_h { |item, quantity| [ item.id, quantity ] }) },
      visible: ->(person) { enabled? && Orders::Access.for(person).requester? })

    # Recent orders on the inventory item's page.
    Inventory.extensions.register_item_panel(:recent_orders, partial: "order_inventory/recent_orders",
      visible: ->(_item, person) { enabled? && !person.nil? })

    # A put-away that couldn't be done shows with the delivery's notice.
    Orders::DeliveriesController.include(OrderInventory::DeliveryNotices)

    # The orders vendor on the Where to buy form.
    Inventory.extensions.register_source_fields(:order_inventory, partial: "order_inventory/source_fields",
      permit: [ :vendor_id ])
  end

  # The note on a movement or units received from a delivery. The request's
  # path in it is linked where the note is shown (OrderInventoryHelper).
  def self.movement_note(order_request)
    path = Rails.application.routes.url_helpers.orders_request_path(order_request)
    "Order request: #{order_request.display_title} (#{path})"
  end

  # The newest order items for an inventory item, on requests the person
  # sees.
  def self.recent_lines(item, person, limit: 5)
    return OrderLine.none if person&.user.nil?

    requests = OrderRequestPolicy::Scope.new(person.user, OrderRequest).resolve
    OrderLine.where(item_type: "Item", item_id: item.id, order_request_id: requests.select(:id))
      .includes(:order_request).order(created_at: :desc).limit(limit)
  end

  # May the person put things away at all, and this item: they see it,
  # and there's a place they can put it.
  def self.puts_away_item?(person, item)
    puts_away?(person) && (item.nil? || Inventory::Access.for(person).sees?(item)) && places_for(person).any?
  end

  # May the person change how many pieces go into stock (record Received
  # of their own count): inventory lets them record Received for the item.
  def self.sets_stock_quantity?(person, item)
    access = Inventory::Access.for(person)
    member_may = access.user? && access.member_kinds.include?("received")
    return access.manager? || member_may if item.nil?

    access.manages?(item.team_id) || (access.sees?(item) && member_may)
  end

  # OrderLine attributes for an item: what it is, its maker and part
  # numbers, its unit, and where to buy it from its preferred source. The
  # source's vendor becomes the line's vendor when it matches one, else an
  # Other store with the source's name.
  def self.line_attributes(item)
    values = item.line_attributes
    vendor = vendor_for(item.preferred_source)
    url = values[:url].presence
    {
      description: values[:name],
      manufacturer: values[:manufacturer],
      manufacturer_part_number: values[:manufacturer_part_number],
      unit: values[:unit],
      vendor_id: vendor&.id,
      other_vendor_name: (values[:vendor_name] if vendor.nil?),
      vendor_part_number: values[:vendor_part_number],
      url: (url if OrderLine.web_link?(url)),
      item: item
    }
  end

  # The vendor for an item source: the one it's linked to, else an active
  # vendor with the same name, else one whose domains match its link.
  def self.vendor_for(source)
    return nil if source.nil?
    return source.vendor if source.vendor_id && source.vendor&.active?

    match_vendor(source.vendor_name, source.url)
  end

  def self.match_vendor(name, url)
    name = name.to_s.strip
    by_name = Vendor.active.where("LOWER(TRIM(name)) = ?", name.downcase).order(:name).first if name.present?
    by_name || (Vendor.for_url(url) if url.present?)
  end

  # { item_id => quantity } on order: bought lines carrying the item, still
  # to come, in the item's stock unit (quantity × units_per).
  def self.on_order(items)
    return {} unless Orders.enabled?

    OrderLine.where(item_type: "Item", item_id: items.map(&:id), status: ON_ORDER_STATUSES)
      .includes(:order_deliveries)
      .each_with_object(Hash.new(0)) do |line, totals|
        totals[line.item_id] += line.to_come_quantity * stock_units_per(line)
      end
  end

  # Pieces in one of the line's units (blank means 1).
  def self.stock_units_per(line)
    [ line.units_per.to_i, 1 ].max
  end

  # The line's item, when it's an inventory item.
  def self.item_for(line)
    line.item if line.item_type == "Item"
  end

  # "Adds 4 units of Motor; label them later."
  def self.units_text(item, pieces)
    "Adds #{pieces} #{'unit'.pluralize(pieces)} of #{item.name}; label them later."
  end

  # "2 packs = 200 each", or "3 each" when a unit holds one piece.
  def self.conversion_text(line, quantity, item: item_for(line))
    per = stock_units_per(line)
    stock_unit = item&.stock_unit || StockUnit.default_unit
    count = quantity.to_i * per
    pieces = "#{count} #{count.abs == 1 ? stock_unit.name : stock_unit.plural_name}"
    return pieces if per == 1

    line_unit = line.unit.presence || "unit"
    "#{quantity.to_i} #{line_unit.pluralize(quantity.to_i)} = #{pieces}"
  end

  # Where a received movement says it came from: the purchase's vendor, else
  # the line's.
  def self.from_name(line)
    purchase = line.purchase
    purchase&.vendor&.name.presence || purchase&.other_vendor_name.presence || line.vendor_name.presence
  end

  # Storage places the person may put things away in.
  def self.places_for(person)
    access = Inventory::Access.for(person)
    places = Location.active.storage.includes(:parent)
    places = places.where(team_id: access.visible_team_ids.to_a) unless access.admin?
    places.sort_by(&:full_name)
  end

  # May this person put deliveries away into inventory at all.
  def self.puts_away?(person)
    enabled? && !person.nil? && Inventory::Access.for(person).user?
  end
end
