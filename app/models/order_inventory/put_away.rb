# Puts a delivery away into inventory: the receiving extension's
# after_receive (orders spec §5). Runs inside the delivery's transaction,
# in a savepoint of its own: a put-away that can't be done is undone on its
# own and noted in OrderInventory::Current.problems (shown with the
# delivery's notice), and never stops the delivery being recorded.
#
# The dialog's fields come as params[:order_inventory]:
#   put_away     "1" to record it ("Track this item")
#   location_id  where it goes
#   quantity     how many go into stock
#   item_id      an existing item, for an item on the order that has none
#   create_item  "1" to make an inventory item from it instead
#
# Only a good delivery goes into stock, and nothing happens unless
# put_away is ticked: an untracked item stays an acknowledgement. The
# delivery itself is the permission (the receiver may receive this
# request) for what came: quantity × units_per, passed on as authorized_by:.
# The place and the inventory item must still be ones the receiver sees,
# and a different number of pieces is taken only from someone inventory
# lets record Received there.
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

    # The received movement or the new units; nil when nothing was put
    # away.
    def call
      return unless OrderInventory.enabled? && @values[:put_away] == "1" && @delivery.good?

      ActiveRecord::Base.transaction(requires_new: true) { put_away! }
    rescue Inventory::Refused, ActiveRecord::RecordInvalid => error
      message = error.is_a?(ActiveRecord::RecordInvalid) ? error.record.errors.full_messages.to_sentence : error.message
      OrderInventory::Current.problems << "#{@line.display_name} was recorded but not put away: #{message}"
      nil
    end

    private

    def put_away!
      item = item!
      location = location!
      if item.tracked?
        ItemUnit.receive!(item: item, location: location, count: pieces, person: @person, note: note, authorized_by: @person)
      else
        StockMovement.record!(kind: :received, item: item, location: location, quantity: stock_quantity(item, location),
          person: @person, reason: OrderInventory.from_name(@line), note: note, authorized_by: @person)
      end
    end

    def access
      Inventory::Access.for(@person)
    end

    # The order item's inventory item, or the one picked or made for it,
    # which the order item is then linked to.
    def item!
      item = OrderInventory.item_for(@line)
      return item.tap { |found| check_seen!(found) } if item

      item =
        if @values[:item_id].present?
          Item.active.find_by(id: @values[:item_id]).tap { |found| check_seen!(found) }
        elsif @values[:create_item] == "1"
          create_item!
        else
          raise Inventory::Refused, "pick the inventory item it is, or create one from it"
        end
      link!(item)
      item
    end

    def check_seen!(item)
      raise Inventory::Refused, "that inventory item isn't one you can see" unless item && access.sees?(item)
    end

    def location!
      location = Location.find_by(id: @values[:location_id])
      raise Inventory::Refused, "pick where to put it away" if location.nil?
      raise Inventory::Refused, "#{location.name} isn't a place you can see" unless access.sees?(location)

      location
    end

    # A new inventory item from what was ordered: what it is, its maker and
    # part numbers, and its store as the preferred source. For inventory
    # managers of the request's team.
    def create_item!
      item = Item.new(OrderInventory::ItemFromLine.attributes(@line))
      unless ItemPolicy.new(@person.user, item).create?
        raise Inventory::Refused, "only an inventory manager can create an inventory item"
      end

      item.home_location = Location.storage.find_by(id: @values[:location_id])
      item.save!
      source = OrderInventory::ItemFromLine.source_attributes(@line)
      item.item_sources.create!(source) if source
      item
    end

    def link!(item)
      @line.update!(item: item)
      @line.order_request.log!(:edited, by: @person, line: @line, changes: { "item" => [ nil, item.name ] })
    end

    # Pieces in the delivery: quantity × units_per.
    def pieces
      @delivery.quantity * OrderInventory.stock_units_per(@line)
    end

    # The pieces that came, or the number typed in the dialog when the
    # receiver may record Received of this item there.
    def stock_quantity(item, location)
      typed = Integer(@values[:quantity].to_s.strip, 10, exception: false)
      return pieces if typed.nil? || typed == pieces
      return pieces unless access.may_record?("received", item, location)

      typed
    end

    def note
      OrderInventory.movement_note(@line.order_request)
    end
  end
end
