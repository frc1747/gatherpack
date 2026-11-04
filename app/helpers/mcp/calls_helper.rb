module Mcp::CallsHelper
  # Types with a page of their own at one ID. A membership's page also needs its team,
  # and a token, which a tool can remove, is linked only while it exists (see below). Others (a badge assignment, a login) aren't linked: a login is reached
  # from its person, listed in the same row.
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
    path = changed_record_path(record)
    path ? link_to(label, path, data: { turbo_frame: "_top" }) : label
  end

  private

  def changed_record_path(record)
    return changed_membership_path(record["id"]) if record["type"] == "Membership"
    return changed_token_path(record["id"]) if record["type"] == "Token"

    helper = CHANGED_RECORD_PATHS[record["type"]]
    public_send(helper, record["id"]) if helper && respond_to?(helper)
  end

  # changed_records holds only type and id, so this looks the team up. Nil once the
  # membership has been removed.
  def changed_membership_path(id)
    team_id = Membership.where(id: id).pick(:team_id)
    team_membership_path(team_id, id) if team_id
  end

  # Nil once the token has been removed, or while its feature is off.
  def changed_token_path(id)
    token_path(id) if respond_to?(:token_path) && Token.exists?(id: id)
  end
end
