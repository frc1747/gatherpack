# Inventory's feature registration. Its menu section is always "Inventory"
# (inventory spec §3.13). The Machines entry becomes one entry per active
# place type that parts get installed on, named by the type's plural
# ("Robots", "Practice bases"), when the menu is drawn.
module Inventory
  class Feature < GatherPack::Feature
    def nav_section
      "Inventory"
    end

    def nav_items
      super.flat_map do |item|
        next [ item ] unless item.path == :inventory_machines_path

        LocationType.installable.map do |type|
          item.dup.tap do |entry|
            entry.label = type.plural_name
            entry.path = -> { inventory_machine_type_path(type) }
          end
        end
      end
    end
  end
end
