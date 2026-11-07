module Checklists
  # One person's results on one checklist as one viewer may see them, from
  # Checklists.status_for. overall and items are ItemStatus; items are the
  # top-level items in order, groups carrying their children. overall is
  # nil when the viewer sees only some items (its level doesn't reach them).
  Status = Struct.new(:person_id, :overall, :items, keyword_init: true) do
    # Every visible item, groups' children included, in order.
    def all_items
      items.flat_map { |item| [ item ] + item.all_children }
    end

    # Unmet first, then almost, then done (the explanation order, §10.5).
    def explained
      order = { "not_met" => 0, "pending" => 1, "met" => 2, "exempt" => 3 }
      items.sort_by.with_index { |item, index| [ order.fetch(item.status, 4), index ] }
    end

    def item(item_id)
      all_items.find { |entry| entry.item&.id == item_id }
    end
  end
end
