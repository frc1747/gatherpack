# One MCP tool call, logged by Mcp::CallLog. Writes record what they changed
# in changed_records (a list of { type, id }), and a write with one main record
# in changed_type/changed_id as well; join to the audit log (versions DB) by those
# and the time. A dry run has an empty list and arguments.dry_run = true.
class McpToolCall < ApplicationRecord
  has_neat_id :mcpc

  OUTCOMES = %w[ok error denied].freeze

  belongs_to :user
  belongs_to :oauth_application, optional: true

  validates :tool, presence: true
  validates :outcome, inclusion: { in: OUTCOMES }

  # Calls logged before changed_records existed have only the two columns.
  def changed_list
    return changed_records if changed_records.present?

    changed_type.present? ? [ { "type" => changed_type, "id" => changed_id } ] : []
  end

  def self.ransackable_attributes(auth_object = nil)
    [ "created_at", "outcome", "tool", "user_id" ]
  end

  def self.ransackable_associations(auth_object = nil)
    []
  end
end
