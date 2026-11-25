require "test_helper"
require_relative "../../../support/mcp_world"

class Mcp::Tools::ListAnnouncementsTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include McpWorld

  setup do
    host! "localhost"
    build_mcp_world
    Announcement.delete_all
    @alpha_post = create_announcement("Alpha post", @alpha, 3.days.ago)
    @beta_post = create_announcement("Beta post", @beta, 2.days.ago)
    @everyone = create_announcement("For everyone", nil, 1.day.ago)
    @past = create_announcement("Long ago", @alpha, 2.years.ago, ends: 1.year.ago)
  end

  def create_announcement(title, team, starts, ends: 1.week.from_now)
    Announcement.create!(title: title, content: "About #{title}", team: team, start_time: starts, end_time: ends)
  end

  def titles(viewer, **options)
    call_tool("list_announcements", user: user(viewer), **options).value["items"].map { |item| item["title"] }
  end

  test "an admin sees all of them, newest first" do
    assert_equal [ "For everyone", "Beta post", "Alpha post", "Long ago" ], titles(:admin)
  end

  test "a team manager and a member see their team's and team-less ones, past ones too" do
    assert_equal [ "For everyone", "Alpha post", "Long ago" ], titles(:alpha_manager)
    assert_equal [ "For everyone", "Alpha post", "Long ago" ], titles(:alpha_member)
  end

  test "a plain member on another team doesn't see this team's" do
    assert_equal [ "For everyone", "Beta post" ], titles(:beta_member)
  end

  test "a guardian on no team sees team-less ones" do
    assert_equal [ "For everyone" ], titles(:guardian)
  end

  test "it lists what the index lists" do
    %i[admin alpha_member beta_member guardian].each do |viewer|
      sign_in user(viewer)
      get announcements_path
      sign_out user(viewer)

      [ @alpha_post, @beta_post, @everyone, @past ].each do |announcement|
        assert_equal response.body.include?(announcement.title), titles(viewer).include?(announcement.title), "#{viewer}, #{announcement.title}"
      end
    end
  end

  test "items carry the details" do
    item = call_tool("list_announcements", user: user(:admin), team_id: @alpha.neat_id).value["items"].first

    assert_equal @alpha_post.neat_id, item["id"]
    assert_equal "About Alpha post", item["content"]
    assert_equal({ "id" => @alpha.neat_id, "name" => "Alpha" }, item["team"])
    assert_equal @alpha_post.start_time.to_i, Time.iso8601(item["start_time"]).to_i
  end

  test "the team filter stays within what the viewer can see" do
    assert_equal [ "Alpha post", "Long ago" ], titles(:admin, team_id: @alpha.neat_id)
    open_team = create_world_team("Open")
    open_team.update!(join_permission: :has_account)
    create_announcement("Open post", open_team, 1.day.ago)
    assert_equal [], titles(:beta_member, team_id: open_team.neat_id)
    assert_equal "Not found", call_tool("list_announcements", user: user(:beta_member), team_id: @alpha.neat_id).error
    assert_equal "Not found", call_tool("list_announcements", user: user(:admin), team_id: "tm_nonsense").error
  end

  test "limit truncates" do
    result = call_tool("list_announcements", user: user(:admin), limit: 2)
    assert_equal 2, result.value["items"].size
    assert result.value["truncated"]
    assert_match(/limit|greater|out of range|maximum/i, call_tool("list_announcements", user: user(:admin), limit: 1000).error.to_s)
  end
end
