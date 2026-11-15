# Inventory's feature registration, with its menu section decided when the
# menu is drawn (inventory spec §3.13): "Purchasing" when another enabled
# feature has menu entries there (a shared section name for anything that
# buys or keeps things), "Inventory" otherwise. Inventory never names any
# other feature; it only looks for the shared section.
module Inventory
  class Feature < GatherPack::Feature
    SHARED_SECTION = "Purchasing"
    OWN_SECTION = "Inventory"

    def nav_section
      shared = GatherPack::Features.all.any? do |feature|
        !feature.is_a?(Inventory::Feature) && feature.enabled? && feature.nav_items.any? &&
          feature.nav_section == SHARED_SECTION
      end
      shared ? SHARED_SECTION : OWN_SECTION
    end
  end
end
