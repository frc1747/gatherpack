require "test_helper"

class AnnouncementNotificationRouterTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @team = teams(:one)
    @team.update!(name: "<b>Alpha</b>")
  end

  def email_bodies
    enqueued_jobs.select { |job| job["job_class"] == "SendEmailJob" }.map { |job| job["arguments"].last }
  end

  test "escapes the title and team name in the email" do
    announcement = Announcement.create!(team: @team, title: %(<a href="https://evil.example/login">Re-enter your password</a>),
      content: "Pack tonight.", start_time: 1.hour.ago, end_time: 1.day.from_now, notify_now: "1")

    AnnouncementNotificationRouter.new(announcement).run

    body = email_bodies.first
    assert body, "expected the team's members to be emailed"
    assert_not body.include?(%(<a href="https://evil.example/login">)), "the title is placed unescaped in the email HTML"
    assert_includes body, "&lt;a href=&quot;https://evil.example/login&quot;&gt;"
    assert_includes body, "&lt;b&gt;Alpha&lt;/b&gt;"
  end

  test "renders the content as Markdown without raw HTML" do
    announcement = Announcement.create!(team: @team, title: "Practice moved",
      content: %(**Bring water.**\n\n<a href="https://evil.example/login">Log in</a><img src="https://evil.example/p.gif">\n\n<form action="https://evil.example"><input name=p></form>),
      start_time: 1.hour.ago, end_time: 1.day.from_now, notify_now: "1")

    AnnouncementNotificationRouter.new(announcement).run

    body = email_bodies.first
    assert body, "expected the team's members to be emailed"
    assert_includes body, "<strong>Bring water.</strong>"
    assert_not body.include?(%(<img src="https://evil.example/p.gif">)), "the email contains the author's raw <img>/<a> HTML"
    assert_not body.include?("<form"), "the email contains the author's raw <form> HTML"
  end
end
