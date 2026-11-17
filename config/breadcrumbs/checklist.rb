crumb :checklists do
  link "Checklists", checklists_path
end

crumb :checklist do |checklist|
  link checklist.new_record? ? "New checklist" : checklist.title, checklist
  parent :checklists
end

crumb :checklist_setup do |checklist|
  link "Edit", edit_checklist_path(checklist, anchor: "items")
  parent :checklist, checklist
end

crumb :checklist_item do |item|
  link item.new_record? ? "New item" : item.label
  parent :checklist_setup, item.checklist
end

crumb :checklist_list do |list|
  link list.identifier_name
  parent :checklist, list.checklist
end
