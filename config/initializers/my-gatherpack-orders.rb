# Orders on the My GatherPack home page and menu. The core knows nothing of
# orders; this adds a to-do section and a Your orders block. Its menu items
# show under the Purchasing heading with the rest of orders and inventory.
# It has no flag of its own: it shows while both features are on.
Rails.application.config.to_prepare do
  MyGatherpack.register_section(:orders, partial: "my_gatherpack/todo_row", column: :todo, position: 20,
    enabled: -> { Orders.enabled? }, items: -> { my_gatherpack_order_items })
  MyGatherpack.register_section(:your_orders, partial: "orders/my_gatherpack_orders", column: :side, position: 10,
    enabled: -> { Orders.enabled? })

  # The share list only exists when the installable app is present.
  Orders::ShareAction.register
end
