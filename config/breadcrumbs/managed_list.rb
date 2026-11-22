crumb :managed_list do |list|
  link list.plural_label, managed_list_path(list.key)
  parent :setup
end

crumb :managed_list_row do |list, row|
  if row.new_record?
    link "New #{list.label.downcase}", new_managed_list_row_path(list.key)
  else
    link row.name_was, edit_managed_list_row_path(list.key, row)
  end
  parent :managed_list, list
end
