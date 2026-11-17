# An announcement as list_announcements and create_announcement return it.
module Mcp::AnnouncementRecords
  SCHEMA = {
    type: "object",
    properties: {
      id: { type: "string" },
      title: { type: "string" },
      content: { type: "string" },
      team: { anyOf: [ Mcp::Tool::REF_SCHEMA, { type: "null" } ] },
      start_time: { type: %w[string null] },
      end_time: { type: %w[string null] }
    },
    required: %w[id title content team start_time end_time]
  }.freeze

  private

  def announcement_json(announcement)
    {
      id: announcement.neat_id,
      title: announcement.title,
      content: announcement.content,
      team: announcement.team && team_json(announcement.team),
      start_time: time_json(announcement.start_time),
      end_time: time_json(announcement.end_time)
    }
  end
end
