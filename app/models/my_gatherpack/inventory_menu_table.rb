module MyGatherpack
  # Places the inventory manager pages in Manage for team managers. The core
  # assigns the whole table when its initializer runs, which can be after this
  # branch's, so the entries are merged in on every assignment.
  module InventoryMenuTable
    ENTRIES = {
      inventory_reorder_path: { manage: 170 },
      inventory_items_path: { manage: 180 },
      inventory_locations_path: { manage: 190 },
      inventory_movements_path: { manage: 200 }
    }.freeze

    def table=(value)
      super(ENTRIES.merge(value || {}))
    end
  end
end
