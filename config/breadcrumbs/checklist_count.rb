# The pages for a count item's sources and credit sit under the item's form.
crumb :checklist_item_form do |item|
  link item.label, edit_checklist_checklist_item_path(item.checklist, item)
  parent :checklist, item.checklist
end

crumb :checklist_count_part do |item, label|
  link label
  parent :checklist_item_form, item
end
