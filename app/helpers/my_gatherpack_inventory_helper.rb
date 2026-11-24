# The home page's inventory to-do: one summary row for the reorder list, read
# from the same query as the Reorder page.
module MyGatherpackInventoryHelper
  def my_gatherpack_inventory_items
    person = current_user.person
    return [] unless person

    reorder = Inventory::Reorder.new(person)
    return [] unless reorder.allowed?

    count = reorder.rows.size
    return [] if count.zero?

    [ MyGatherpack::Item.new(title: "#{pluralize(count, "item")} running low", detail: "On the reorder list",
      path: inventory_reorder_path, action: "Open Reorder", icon: "cart-flatbed") ]
  end
end
