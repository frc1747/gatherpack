require "test_helper"
require_relative "../../../support/mcp_world"

class Mcp::Tools::CreateAnnouncementTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper
  include Devise::Test::IntegrationHelpers
  include McpWorld

  setup do
    host! "localhost"
    build_mcp_world
  end

  def post_as(viewer, team: nil, **options)
    arguments = { title: "Meeting moved", content: "To *Tuesday*." }.merge(options)
    arguments[:team_id] = team.neat_id if team
    call_tool("create_announcement", user: user(viewer), **arguments)
  end

  # The email jobs the block enqueues, as [recipient, subject, content].
  def emails
    clear_enqueued_jobs
    yield
    enqueued_jobs.select { |job| job["job_class"] == "SendEmailJob" }.map { |job| job["arguments"].last(3) }.sort
  end

  test "an admin posts to everyone, without a team, and gets it back in the read tool's shape" do
    travel_to Time.utc(2026, 3, 12, 12, 0) do
      result = post_as(:admin)

      announcement = Announcement.find(result.changed.id)
      assert_equal({
        "id" => announcement.neat_id,
        "title" => "Meeting moved",
        "content" => "To *Tuesday*.",
        "team" => nil,
        "start_time" => Time.current.iso8601,
        "end_time" => 1.week.from_now.iso8601,
        "notified" => 0
      }, result.value)
      read = call_tool("list_announcements", user: user(:admin)).value["items"].find { |item| item["id"] == announcement.neat_id }
      assert_equal result.value.except("notified"), read
    end
  end

  test "a team manager posts to their team, and to a sub-team" do
    child = create_world_team("Kid", parent: @alpha)

    assert_equal "Alpha", post_as(:alpha_manager, team: @alpha).value.dig("team", "name")
    assert_nil post_as(:alpha_manager, team: child).error
  end

  test "a team manager can't post to another team, or to everyone" do
    other = open_team

    assert_refused("Not allowed", Announcement, AuditLog) { post_as(:alpha_manager) }
    assert_refused("Not allowed", Announcement, AuditLog) { post_as(:alpha_manager, team: other) }
  end

  test "a plain member and a guardian can't post" do
    assert_refused("Not allowed", Announcement, AuditLog) { post_as(:alpha_member, team: @alpha) }
    assert_refused("Not allowed", Announcement, AuditLog) { post_as(:beta_member) }
    assert_refused("Not allowed", Announcement, AuditLog) { post_as(:guardian) }
  end

  test "a team the viewer can't see is not found" do
    assert_refused("Not found", Announcement, AuditLog) { post_as(:alpha_manager, team: @beta) }
    assert_refused("Not found", Announcement, AuditLog) { post_as(:admin, team_id: "tm_nonsense") }
  end

  test "times are taken as given, in the app's zone or with an offset, and the end may come first as on the page" do
    result = post_as(:admin, starts_at: "2026-04-01T09:00:00Z", ends_at: "2026-04-02T09:00:00+02:00")
    assert_equal Time.utc(2026, 4, 1, 9), result.changed.start_time
    assert_equal Time.utc(2026, 4, 2, 7), result.changed.end_time

    assert_nil post_as(:admin, starts_at: "2026-04-02T09:00:00Z", ends_at: "2026-04-01T09:00:00Z").error
  end

  test "malformed times, and blank or wrongly typed values, change nothing" do
    [ "tomorrow", "2026-02-31T09:00:00", "2026-04-01", "" ].each do |bad|
      assert_refused(/starts_at must be a time/, Announcement, AuditLog) { post_as(:admin, starts_at: bad) }
      assert_refused(/ends_at must be a time/, Announcement, AuditLog) { post_as(:admin, ends_at: bad) }
    end
    assert_refused(/Title can't be blank/, Announcement, AuditLog) { post_as(:admin, title: "") }
    assert_refused(/Content can't be blank/, Announcement, AuditLog) { post_as(:admin, content: "") }
    assert_refused(/title/, Announcement, AuditLog) { call_tool("create_announcement", user: user(:admin), content: "x") }
    [ "no", "true", 1, nil ].each do |bad|
      assert_refused(/notify_now/, Announcement, AuditLog) { post_as(:admin, notify_now: bad) }
    end
  end

  test "the page's own names for the dates are refused, not dropped" do
    assert_refused(/start_time/, Announcement, AuditLog) { post_as(:admin, start_time: "2026-04-01T09:00:00Z") }
  end

  test "without notify_now nobody is emailed" do
    jobs = emails do
      assert_equal 0, post_as(:admin, team: @alpha).value["notified"]
      assert_equal 0, post_as(:admin, team: @alpha, notify_now: false).value["notified"]
    end
    assert_empty jobs
  end

  test "notify_now emails the team as the page does, and reports how many" do
    result = nil
    jobs = emails { result = post_as(:alpha_manager, team: @alpha, notify_now: true) }

    assert_equal 3, result.value["notified"]
    assert_equal %w[alphamanager@example.com alphamember@example.com ward@example.com], jobs.map(&:first)

    page_jobs = emails do
      sign_in user(:alpha_manager)
      post announcements_path, params: { announcement: { title: "Meeting moved", content: "To *Tuesday*.", team_id: @alpha.id, notify_now: "1",
        start_time: Time.current, end_time: 1.day.from_now } }
    end
    assert_equal page_jobs, jobs
  end

  test "a team-less notice goes to everyone with a login, as the page's does" do
    result = nil
    jobs = emails { result = post_as(:admin, notify_now: true) }
    page_jobs = emails do
      sign_in user(:admin)
      post announcements_path, params: { announcement: { title: "Meeting moved", content: "To *Tuesday*.", notify_now: "1", start_time: Time.current, end_time: 1.day.from_now } }
    end

    assert_operator result.value["notified"], :>=, 7
    assert_equal result.value["notified"], jobs.size
    assert_equal page_jobs, jobs
  end

  test "a refused notice emails nobody" do
    jobs = emails { assert_equal "Not allowed", post_as(:alpha_member, team: @alpha, notify_now: true).error }
    assert_empty jobs
  end

  test "someone without a login isn't counted" do
    Person.create!(first_name: "NoLogin", last_name: "World").memberships.create!(team: @alpha)

    assert_equal 3, post_as(:admin, team: @alpha, notify_now: true).value["notified"]
  end

  test "another job the router's run doesn't enqueue isn't counted" do
    Hook.create!(name: "Mailer", event: "announcements - create", code: %(SendEmailJob.perform_later(nil, "hook@example.com", "s", "c")))

    assert_equal 3, post_as(:admin, team: @alpha, notify_now: true).value["notified"]
  end

  test "it allows and refuses as the page does" do
    [
      [ :admin, nil ], [ :admin, @alpha ], [ :admin, @beta ],
      [ :alpha_manager, @alpha ], [ :alpha_manager, nil ], [ :alpha_manager, @beta ],
      [ :alpha_member, @alpha ], [ :beta_member, @beta ], [ :beta_member, nil ], [ :guardian, nil ]
    ].each do |viewer, team|
      page = page_changes_rows?(Announcement, as: user(viewer)) do
        post announcements_path, params: { announcement: { title: "T", content: "C", team_id: team&.id, start_time: Time.current, end_time: 1.day.from_now } }
      end
      tool = changes_rows?(Announcement) { post_as(viewer, team: team) }

      assert_equal page, tool, "#{viewer} posting to #{team&.name.inspect}"
    end
  end

  test "the audit log has the token's user, and hooks run" do
    result = post_as(:admin)
    assert_equal user(:admin).id, result.changed.versions.last.whodunnit

    assert_hook_runs("announcements - create") { post_as(:admin) }
  end

  test "a read token and the setting being off refuse it" do
    assert_refused("Not allowed", Announcement) { post_as(:admin, scopes: "mcp_read") }
    assert_refused("Writes disabled", Announcement) { post_as(:admin, writes_enabled: false) }
  end

  private

  def open_team
    team = create_world_team("Open")
    team.update!(join_permission: :has_account)
    team
  end
end
