# MCP connector for person fields: get_person_fields, and a "fields" key on
# get_person while the feature is on. Named to sort after mcp.rb, which
# resets the registry.
Rails.application.config.to_prepare do
  next unless Mcp.feature_registered?(:person_fields)

  Mcp.register_tool(Mcp::Tools::GetPersonFields)
  Mcp.person_extensions << lambda do |person, viewer|
    GatherPack::Features.enabled?(:person_fields) ? { fields: Mcp::Tools::GetPersonFields.groups_for(person, viewer) } : {}
  end
end
