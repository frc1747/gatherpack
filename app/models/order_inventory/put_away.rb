# Puts a delivery away into inventory: the receiving extension's
# after_receive (orders spec §5). Runs inside the delivery's transaction,
# so a refusal undoes the delivery too; it's raised as Orders::Refused,
# which the receive dialog shows.
#
# The dialog's fields come as params[:order_inventory]:
#   put_away     "1" to record it ("Track this item")
#   location_id  where it goes
#   quantity     how many go into stock (default delivery quantity × units_per)
#   item_id      an existing item, for a line that has none
#   create_item  "1" to make an item from the line instead
#
# Only a good delivery goes into stock, and nothing happens unless
# put_away is ticked: an untracked line stays an acknowledgement. The
# delivery itself is the permission (the receiver may receive this
# request), passed on as authorized_by:; the place and the item must still
# be ones the receiver sees.
module OrderInventory
  class PutAway
    def self.call(delivery, params)
      new(delivery, params).call
    end

    def initialize(delivery, params)
      @delivery = delivery
      @line = delivery.order_line
      @person = delivery.received_by
      values = params.respond_to?(:to_unsafe_h) ? params.to_unsafe_h : params.to_h
      @values = values.with_indifferent_access.fetch(:order_inventory, {}).to_h.with_indifferent_access
    end

    def call
      return unless OrderInventory.enabled? && @values[:put_away] == "1" && @delivery.good?

      item = item!
      location = location!
      if item.tracked?
        ItemUnit.receive!(item: item, location: location, count: pieces, person: @person, note: note, authorized_by: @person)
      else
        StockMovement.record!(kind: :received, item: item, location: location, quantity: stock_quantity, person: @person,
          reason: OrderInventory.from_name(@line), note: note, authorized_by: @person)
      end
    rescue Inventory::Refused => error
      raise Orders::Refused, error.message
    end

    private

    def access
      Inventory::Access.for(@person)
    end

    # The line's item, or the one picked or made for it, which the line
    # is then linked to.
    def item!
      item = OrderInventory.item_for(@line)
      return item.tap { |found| check_seen!(found) } if item

      item =
        if @values[:item_id].present?
          Item.active.find_by(id: @values[:item_id]).tap { |found| check_seen!(found) }
        elsif @values[:create_item] == "1"
          create_item!
        else
          raise Inventory::Refused, "Pick the item this is, or create one from this item"
        end
      link!(item)
      item
    end

    def check_seen!(item)
      raise Inventory::Refused, "That item isn't one you can see" unless item && access.sees?(item)
    end

    def location!
      location = Location.find_by(id: @values[:location_id])
      raise Inventory::Refused, "Pick where to put it away" if location.nil?
      raise Inventory::Refused, "#{location.name} isn't a place you can see" unless access.sees?(location)

      location
    end

    # A new item from the line: what it is, its maker and part numbers, and
    # its store as the preferred source. For inventory managers of the
    # request's team.
    def create_item!
      item = Item.new(OrderInventory::ItemFromLine.attributes(@line))
      unless ItemPolicy.new(@person.user, item).create?
        raise Inventory::Refused, "Only an inventory manager can create an item"
      end

      item.home_location = Location.find_by(id: @values[:location_id], kind: "storage")
      item.save!
      source = OrderInventory::ItemFromLine.source_attributes(@line)
      item.item_sources.create!(source) if source
      item
    rescue ActiveRecord::RecordInvalid => error
      raise Inventory::Refused, error.record.errors.full_messages.to_sentence
    end

    def link!(item)
      @line.update!(item: item)
      @line.order_request.log!(:edited, by: @person, line: @line, changes: { "item" => [ nil, item.name ] })
    end

    # Pieces in the delivery: quantity × units_per.
    def pieces
      @delivery.quantity * OrderInventory.stock_units_per(@line)
    end

    # The number typed in the dialog, else the delivery's pieces.
    def stock_quantity
      typed = @values[:quantity].to_s.strip
      typed.empty? ? pieces : typed
    end

    def note
      path = Rails.application.routes.url_helpers.orders_request_path(@line.order_request)
      "Order request: #{@line.order_request.display_title} (#{path})"
    end
  end
end
