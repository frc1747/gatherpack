# One MCP tool call, logged by Mcp::CallLog. Writes record what they changed
# in changed_type/changed_id; join to the audit log (versions DB) by those
# and the time.
class McpToolCall < ApplicationRecord
  has_neat_id :mcpc

  OUTCOMES = %w[ok error denied].freeze

  belongs_to :user
  belongs_to :oauth_application, optional: true

  validates :tool, presence: true
  validates :outcome, inclusion: { in: OUTCOMES }

  def self.ransackable_attributes(auth_object = nil)
    [ "created_at", "outcome", "tool", "user_id" ]
  end

  def self.ransackable_associations(auth_object = nil)
    []
  end
end
