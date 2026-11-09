# Announcements the viewer can see. Mirrors AnnouncementsController#index (line 6:
# policy_scope(Announcement), which is their teams' and team-less ones), including ones
# outside their dates, as the index lists them. Newest first, where the index goes by end
# time. The team filter is the index's team_id_eq, offering policy_scope(Team)
# (announcements/index line 17). No policy check beyond the scope: AnnouncementPolicy
# doesn't define show?.
class Mcp::Tools::ListAnnouncements < Mcp::Tool
  include Mcp::AnnouncementRecords

  tool_name "list_announcements"
  description "Announcements you can see, newest first, including past and scheduled ones. Optionally only one team's. A team you can't see is \"Not found\"."
  scope :read
  input_schema(
    properties: {
      team_id: { type: "string", description: "Only this team's announcements (tm_ ID)" },
      limit: limit_property
    }
  )
  output_schema(
    type: "object",
    properties: { items: { type: "array", items: Mcp::AnnouncementRecords::SCHEMA }, truncated: { type: "boolean" } },
    required: %w[items truncated]
  )

  def call(team_id: nil, limit: DEFAULT_LIMIT)
    announcements = ctx.policy_scope(Announcement)
    announcements = announcements.where(team_id: ctx.find(Team, team_id).id) if team_id

    list(announcements.includes(:team).order(start_time: :desc, id: :desc), limit: limit) { |announcement| announcement_json(announcement) }
  end
end
