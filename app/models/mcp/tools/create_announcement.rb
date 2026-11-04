# Creates an announcement, as AnnouncementsController#create does.
#
# Mirrors: create (lines 25-29: build from announcement_params, line 68: title, content,
# start_time, end_time, team_id and notify_now; authorize create?; save; run
# AnnouncementNotificationRouter). AnnouncementPolicy#create? is admins, and managers of
# the announcement's team: a team-less one, which goes to everyone, is admin only. The
# dates default as the new form fills them in (line 17). The model doesn't require the end
# to be after the start, so neither does this. The router sends only with notify_now, and
# reports nothing back, so notified counts the emails it enqueued.
#
# The schema is closed: the page calls its dates start_time and end_time, and a client
# sending those must not get the default dates with a success.
class Mcp::Tools::CreateAnnouncement < Mcp::Tool
  include Mcp::AnnouncementRecords

  tool_name "create_announcement"
  description "Post an announcement, as New Announcement does on the Announcements page. With notify_now it emails everyone on the team and its sub-teams, or everyone " \
    "if it has no team, so confirm the text first. Only admins can post without a team; \"Not allowed\" for a team you don't manage. Returns it with the number of people notified."
  scope :write
  input_schema(
    properties: {
      title: { type: "string", description: "The title" },
      content: { type: "string", description: "The text, in Markdown" },
      team_id: { type: "string", description: "The team's ID (tm_). Without one it goes to everyone (admins only)" },
      starts_at: { type: "string", description: "First shown, ISO 8601 date-time (default now)" },
      ends_at: { type: "string", description: "Last shown, ISO 8601 date-time (default a week from now)" },
      notify_now: { type: "boolean", description: "Email the audience now (default false)" }
    },
    required: %w[title content],
    closed: true
  )
  output_schema(
    type: "object",
    properties: Mcp::AnnouncementRecords::SCHEMA[:properties].merge(notified: { type: "integer" }),
    required: Mcp::AnnouncementRecords::SCHEMA[:required] + %w[notified]
  )

  def call(title:, content:, team_id: nil, starts_at: nil, ends_at: nil, notify_now: false)
    team = team_id && ctx.find(Team, team_id)
    announcement = Announcement.new(title: title, content: content, team: team, notify_now: notify_now ? "1" : "0")
    ctx.authorize!(announcement, :create?)

    announcement.start_time = starts_at ? parse_time(starts_at, "starts_at") : Time.current
    announcement.end_time = ends_at ? parse_time(ends_at, "ends_at") : Time.current + 1.week
    invalid_argument!(announcement.errors.full_messages.to_sentence) unless announcement.save

    changed!(announcement)
    announcement_json(announcement).merge(notified: notify(announcement))
  end

  private

  # The router's emails only: a hook on this thread or a job from another isn't one.
  def notify(announcement)
    count = 0
    thread = Thread.current
    counter = ->(event) { count += 1 if Thread.current == thread && event.payload[:job].is_a?(SendEmailJob) && event.payload[:job].successfully_enqueued? }
    ActiveSupport::Notifications.subscribed(counter, "enqueue.active_job") { AnnouncementNotificationRouter.new(announcement).run }
    count
  end

  def parse_time(value, name)
    raise ArgumentError unless value.match?(Mcp::PunchRecords::TIME_FORMAT)

    Date.iso8601(value[0, 10])
    Time.zone.iso8601(value)
  rescue ArgumentError
    invalid_argument!("#{name} must be a time like 2026-03-31T18:00:00")
  end
end
