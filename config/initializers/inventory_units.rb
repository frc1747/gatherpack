# Tracked units on the item page (inventory spec §3.15): units by place,
# and for managers the tracking switch and the readings a check asks for.
Rails.application.config.to_prepare do
  Inventory.extensions.register_item_panel(:units, partial: "inventory/units/item_panel",
    visible: ->(item, person) { item.tracked? || (person&.user.present? && ItemPolicy.new(person.user, item).start_tracking?) })
end
