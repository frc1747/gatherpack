# MCP connector for person fields: list_person_fields, get_person_fields,
# set_person_field, update_person_fields, and a "fields" key on get_person while the
# feature is on, and a filter that applies the built-in fields' read rules to
# get_person's contact details. Named to sort after mcp.rb, which resets the registry.
# The page's values are filtered by name (person_field_values); a tool's aren't.
# set_person_field's is "value", update_person_fields' is "values" (a whole object).
Rails.application.config.filter_parameters += [ "params.arguments.value", "params.arguments.values" ]

Rails.application.config.to_prepare do
  next unless Mcp.feature_registered?(:person_fields)

  Mcp.register_tool(Mcp::Tools::ListPersonFields)
  Mcp.register_tool(Mcp::Tools::GetPersonFields)
  Mcp.register_tool(Mcp::Tools::SetPersonField)
  Mcp.register_tool(Mcp::Tools::UpdatePersonFields)

  # Built-in fields are enforced whether or not the feature flag is on
  # (PersonField.in_use), so this filter doesn't check the flag. A key is kept
  # only when its field is readable by the viewer and shown on the profile, as
  # people/_fields decides; with no field row, nothing is shown there, so the
  # key is left out.
  Mcp.person_filters << lambda do |person, viewer|
    person.readable_fields_for(viewer).select { |field| field.system? && field.show_on_profile }
      .map { |field| field.system_source.delete_prefix("user.") }
      .select { |key| Mcp::Tools::GetPerson::PROFILE_FIELD_KEYS.include?(key) }
  end
  Mcp.person_extensions << lambda do |person, viewer|
    GatherPack::Features.enabled?(:person_fields) ? { fields: Mcp::Tools::GetPersonFields.groups_for(person, viewer) } : {}
  end
end
