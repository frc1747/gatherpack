# MCP's columns for the person merge registry. Guarded, so this branch runs
# without feature/person-merge. to_prepare runs after every initializer, so
# the registry is loaded by then whatever the file order.
Rails.application.config.to_prepare do
  next unless defined?(GatherPack::PersonMerge)

  merge = GatherPack::PersonMerge

  # What a login did through MCP follows the login that stays.
  merge.register :mcp_tool_calls, :user_id, owner: :user, label: "Assistant calls"
  # The record a call changed is a person or a login; both are covered.
  { person: "", user: " (login)" }.each do |owner, suffix|
    merge.register :mcp_tool_calls, :changed_id, type_column: :changed_type, owner: owner,
      label: "Assistant calls that changed them#{suffix}"
  end
end
