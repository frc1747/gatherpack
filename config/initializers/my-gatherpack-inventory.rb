# Inventory on the My GatherPack home page and menu. The core knows nothing of
# inventory; this adds a to-do row for the reorder list and the Manage
# placements. It has no flag of its own: it shows while both features are on.
Rails.application.config.to_prepare do
  MyGatherpack.register_section(:inventory, partial: "my_gatherpack/todo_row", column: :todo, position: 30,
    enabled: -> { Inventory.enabled? }, items: -> { my_gatherpack_inventory_items })

  # Inventory stays in More; the rest are for the people who run it.
  MyGatherpack::Menu.singleton_class.prepend(MyGatherpack::InventoryMenuTable)
  MyGatherpack::Menu.table = MyGatherpack::Menu.table

  # An inventory manager who manages no team still gets Manage for these.
  MyGatherpack::Menu.register_manager_check(:inventory, paths: %i[
    inventory_reorder_path inventory_items_path inventory_locations_path inventory_movements_path
  ]) do |person|
    Inventory.enabled? && Inventory::Access.for(person).manager?
  end
end
