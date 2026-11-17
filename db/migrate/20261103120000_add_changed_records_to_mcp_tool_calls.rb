class AddChangedRecordsToMcpToolCalls < ActiveRecord::Migration[8.1]
  def change
    add_column :mcp_tool_calls, :changed_records, :jsonb, null: false, default: []
  end
end
