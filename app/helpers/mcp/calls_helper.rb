module Mcp::CallsHelper
  # Types with a page of their own. Others (a membership, a badge assignment, a
  # login) are reached through a parent, so they aren't linked.
  CHANGED_RECORD_PATHS = {
    "Person" => :person_path,
    "Team" => :team_path,
    "Badge" => :badge_path,
    "Event" => :event_path
  }.freeze

  # A link to a { "type", "id" } entry of McpToolCall#changed_list, or its text
  # where it has no page. Some routes exist only while their feature is on.
  def changed_record_link(record)
    label = "#{record["type"]} #{record["id"]}"
    helper = CHANGED_RECORD_PATHS[record["type"]]
    helper && respond_to?(helper) ? link_to(label, public_send(helper, record["id"]), data: { turbo_frame: "_top" }) : label
  end
end
