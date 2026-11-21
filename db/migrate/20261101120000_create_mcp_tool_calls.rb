class CreateMcpToolCalls < ActiveRecord::Migration[8.1]
  def change
    create_table :mcp_tool_calls, id: :uuid do |t|
      t.references :user, type: :uuid, null: false, foreign_key: true
      t.references :oauth_application, type: :uuid, foreign_key: { on_delete: :nullify }
      t.string :tool, null: false
      t.jsonb :arguments, null: false, default: {}
      t.string :outcome, null: false
      t.string :error_message
      t.string :changed_type
      t.uuid :changed_id
      t.integer :duration_ms
      t.datetime :created_at, null: false
    end

    add_index :mcp_tool_calls, :created_at
  end
end
