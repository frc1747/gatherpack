# The person_field checklist item kind. Registering it also watches
# PersonFieldValue (and Person and User, for the built-in fields) so a change
# marks the people of the checklists that test a field.
Rails.application.config.to_prepare do
  next unless defined?(Checklists) && Checklists.respond_to?(:register_item_kind)

  Checklists.register_item_kind(:person_field, Checklists::Kinds::PersonField)
end
