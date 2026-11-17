# Inventory on the My GatherPack home page and menu. The core knows nothing of
# inventory; this adds a to-do row for the reorder list. Its menu items show
# under the Purchasing heading with the rest of orders and inventory.
# It has no flag of its own: it shows while both features are on.
Rails.application.config.to_prepare do
  MyGatherpack.register_section(:inventory, partial: "my_gatherpack/todo_row", column: :todo, position: 30,
    enabled: -> { Inventory.enabled? }, items: -> { my_gatherpack_inventory_items })
end
