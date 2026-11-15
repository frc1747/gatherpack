# Orders on the My GatherPack home page and menu. The core knows nothing of
# orders; this adds a to-do section, a Your orders block and the Manage
# placements. It has no flag of its own: it shows while both features are on.
# The name sorts after my_gatherpack.rb, which assigns the menu table.
Rails.application.config.to_prepare do
  MyGatherpack.register_section(:orders, partial: "my_gatherpack/todo_row", column: :todo, position: 20,
    enabled: -> { Orders.enabled? }, items: -> { my_gatherpack_order_items })
  MyGatherpack.register_section(:your_orders, partial: "orders/my_gatherpack_orders", column: :side, position: 10,
    enabled: -> { Orders.enabled? })

  # Orders and To receive stay in More; the rest are for the people who run it.
  MyGatherpack::Menu.table.merge!(
    orders_approvals_path: { manage: 120 },
    to_buy_orders_purchases_path: { manage: 130 },
    orders_vendors_path: { manage: 140 },
    orders_funding_sources_path: { manage: 150 },
    orders_reports_path: { manage: 160 }
  )

  # An approver or buyer who manages no team still gets Manage for these.
  MyGatherpack::Menu.register_manager_check(:orders, paths: %i[
    orders_approvals_path to_buy_orders_purchases_path orders_vendors_path orders_funding_sources_path orders_reports_path
  ]) do |person|
    Orders.enabled? && (access = Orders::Access.for(person)) && (access.approver? || access.buyer?)
  end
end
