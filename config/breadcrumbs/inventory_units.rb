# Tracked units and machines (inventory spec §3.15).
crumb :inventory_machines do
  link "Inventory", inventory_root_path
  link "Machines", inventory_machines_path
end

crumb :inventory_machine do |machine|
  link machine.name, inventory_machine_path(machine)
  parent :inventory_machines
end

crumb :inventory_units do
  link "Inventory", inventory_root_path
  link "Find a part", inventory_units_path
end

crumb :inventory_tracked_item do |item|
  link "Inventory", inventory_root_path
  link item.name, inventory_item_path(item)
end

crumb :inventory_unit do |unit|
  link unit.identifier_name, inventory_unit_path(unit)
  parent :inventory_tracked_item, unit.item
end

crumb :inventory_unit_action do |unit, title|
  link title
  parent :inventory_unit, unit
end

crumb :inventory_item_units_new do |item|
  link "Add units"
  parent :inventory_tracked_item, item
end

crumb :inventory_item_readings do |item|
  link "Readings"
  parent :inventory_tracked_item, item
end
