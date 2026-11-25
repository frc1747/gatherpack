# Shows a note from a received movement or unit (OrderInventory.movement_note)
# with the order request it came from as a link.
module OrderInventoryHelper
  REQUEST_PATH = %r{/orders/requests/ordr_[a-z0-9]+}

  def order_inventory_note(note)
    return "" if note.blank?

    parts = note.to_s.split(/(#{REQUEST_PATH})/o)
    safe_join(parts.map { |part| part.match?(/\A#{REQUEST_PATH}\z/o) ? link_to("open the order request", part) : part })
  end
end
