require "test_helper"

class DeliverInfodumpJobTest < ActiveJob::TestCase
  setup do
    @person = people(:one)
    teams(:one).update!(name: "<b>Alpha</b>")
  end

  test "escapes names and titles and filters HTML in the infodump email" do
    @person.update!(display_name: "<i>Alice</i>")
    Announcement.create!(team: teams(:one), title: %(<a href="https://evil.example/login">Re-enter your password</a>),
      content: %(**Bring water.**\n\n<img src="https://evil.example/p.gif">),
      start_time: 1.hour.ago, end_time: 1.day.from_now)

    DeliverInfodumpJob.perform_now(@person)

    job = enqueued_jobs.find { |j| j["job_class"] == "SendEmailJob" }
    assert job, "expected the infodump to be emailed"
    body = job["arguments"].last
    assert_not body.include?(%(<a href="https://evil.example/login">)), "the announcement title is placed unescaped in the infodump"
    assert_not body.include?(%(<img src="https://evil.example/p.gif">)), "the infodump contains the author's raw <img> HTML"
    assert_includes body, "&lt;i&gt;Alice&lt;/i&gt;"
    assert_includes body, "&lt;b&gt;Alpha&lt;/b&gt;"
    assert_includes body, "<strong>Bring water.</strong>"
  end
end
