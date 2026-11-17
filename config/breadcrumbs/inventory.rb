crumb :inventory do
  link "Inventory", inventory_stock_path
end

crumb :inventory_items do
  link "Items", inventory_items_path
  parent :inventory
end

crumb :inventory_item do |item|
  link item.new_record? ? "New item" : item.name, item.new_record? ? new_inventory_item_path : inventory_item_path(item)
  parent :inventory
end

crumb :inventory_item_source do |item_source|
  link item_source.new_record? ? "New place to buy" : item_source.vendor_name
  parent :inventory_item, item_source.item
end

crumb :inventory_locations do
  link "Places", inventory_locations_path
  parent :inventory
end

crumb :inventory_location do |location|
  link location.new_record? ? "New place" : location.name,
    location.new_record? ? new_inventory_location_path : inventory_location_path(location)
  if location.parent
    parent :inventory_location, location.parent
  else
    parent :inventory_locations
  end
end

crumb :inventory_count do |location|
  link "Count this place", count_inventory_location_path(location)
  parent :inventory_location, location
end

crumb :inventory_movement_new do |item|
  link "Record a change"
  parent :inventory_item, item
end

crumb :inventory_movements do
  link "Changes", inventory_movements_path
  parent :inventory
end

crumb :inventory_reorder do
  link "Reorder", inventory_reorder_path
  parent :inventory
end

crumb :inventory_labels do
  link "Labels", inventory_labels_path
  parent :inventory_locations
end

crumb :inventory_import do
  link "Import", new_inventory_import_path
  parent :inventory_items
end

crumb :inventory_setup do
  link "Setup", inventory_setup_path
  parent :inventory
end
