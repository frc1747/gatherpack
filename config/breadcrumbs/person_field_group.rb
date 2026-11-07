crumb :person_field_groups do
  link "Person Field Sections", person_field_groups_path
  parent :setup
end

crumb :person_field_group do |person_field_group|
  link person_field_group.new_record? ? "New section" : person_field_group.identifier_name, person_field_group.new_record? ? new_person_field_group_path : edit_person_field_group_path(person_field_group)
  parent :person_field_groups
end
