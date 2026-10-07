crumb :person_fields do
  link "Person Fields", person_fields_path
  parent :setup
end

crumb :person_field do |person_field|
  link person_field.new_record? ? "New person field" : person_field.identifier_name, person_field.new_record? ? new_person_field_path : edit_person_field_path(person_field)
  parent :person_fields
end

crumb :person_field_preview do
  link "Preview as…", preview_person_fields_path
  parent :person_fields
end
