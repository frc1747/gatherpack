# The list page a housekeeping screen was reached from (a route helper name).
crumb :housekeeping_from do |label, path_helper|
  link label, context.public_send(path_helper)
  parent :root
end

crumb :housekeeping_list do |type, archived|
  link "#{archived ? "Archived" : "Old"} #{type.label.downcase}", housekeeping_list_path(type.key, archived: ("1" if archived))
  if type.list_path && context.respond_to?(type.list_path)
    parent :housekeeping_from, type.label, type.list_path
  else
    parent :root
  end
end

crumb :housekeeping_preview do |type, archived, verb|
  link "Check before you #{verb.downcase}"
  parent :housekeeping_list, type, archived
end

crumb :housekeeping_purge do |purge|
  link "Clear #{purge.label.downcase_first}", housekeeping_purge_path(purge.key)
  page_path = :"#{purge.page}_path"
  if context.respond_to?(page_path)
    parent :housekeeping_from, purge.page.to_s.humanize, page_path
  else
    parent :root
  end
end
