# Inventory's feature registration. Its menu section is always "Inventory"
# (inventory spec §3.13). The Machines entry is named and shown as Inventory
# setup says, when the menu is drawn.
module Inventory
  class Feature < GatherPack::Feature
    def nav_section
      "Inventory"
    end

    def nav_items
      super.filter_map do |item|
        next item unless item.path == :inventory_machines_path
        next unless Inventory.machines?

        item.dup.tap { |named| named.label = Inventory.machine_word(count: :many, capitalize: true) }
      end
    end
  end
end
