require "test_helper"

class GatherPack::DigestsTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @path = Rails.root.join("tmp", "settings-digests-test-#{Process.pid}.pstore").to_s
    File.delete(@path) if File.exist?(@path)
    @original_store = Settings.instance.store
    Settings.instance.store = PStore.new(@path, true)
    Settings[:time_zone] = "America/Chicago"
    Settings[:title] = "Example Club"

    @alice = people(:one)
    @bob = people(:two)
    @calls = []
    @delivery = { test_tasks: :daily, test_news: :weekly }
    calls = @calls
    delivery = @delivery
    alice = @alice

    GatherPack::Digests.register(:test_tasks, label: "Tasks", delivery: -> { delivery[:test_tasks] },
      build: ->(person, since:) {
        calls << [ :test_tasks, person, since ]
        next unless person == alice

        GatherPack::Digests::Section.new(body: "<p>Two tasks for <b>#{ERB::Util.h("A & B")}</b></p>", link: "https://example.com/tasks?a=1&b=2")
      })
    GatherPack::Digests.register(:test_news, label: "News", delivery: -> { delivery[:test_news] },
      build: ->(person, since:) {
        calls << [ :test_news, person, since ]
        next unless person == alice

        GatherPack::Digests::Section.new(heading: "Club <news>", body: "<p>Something new</p>")
      })

    Announcement.delete_all
  end

  teardown do
    GatherPack::Digests.unregister(:test_tasks)
    GatherPack::Digests.unregister(:test_news)
    Settings.instance.store = @original_store
    File.delete(@path) if File.exist?(@path)
  end

  def turn_on
    Settings[:feature_digests] = "true"
  end

  # 13:30 UTC is 7:30 in Chicago, after the default 7:00.
  def morning
    Time.utc(2026, 11, 17, 13, 30)
  end

  def sent_emails
    enqueued_jobs.select { |job| job[:job] == SendEmailJob }.map { |job| ActiveJob::Arguments.deserialize(job[:args]) }
  end

  test "takes each section's delivery from the feature and treats anything unknown as off" do
    assert_equal :weekly, GatherPack::Digests[:test_news].delivery

    @delivery[:test_news] = "both"
    assert_equal :both, GatherPack::Digests[:test_news].delivery

    @delivery[:test_news] = :hourly
    assert_equal :off, GatherPack::Digests[:test_news].delivery

    @delivery[:test_news] = nil
    assert_equal :off, GatherPack::Digests[:test_news].delivery
  end

  test "handles a section only while summaries are on" do
    assert_not GatherPack::Digests.handles?(:test_tasks)

    turn_on
    assert GatherPack::Digests.handles?(:test_tasks)
    assert_not GatherPack::Digests.handles?(:test_unknown)

    @delivery[:test_tasks] = :off
    assert GatherPack::Digests.handles?(:test_tasks)
  end

  test "daily combines every daily section into one email per person" do
    turn_on
    @delivery[:test_news] = :daily

    DeliverDailyDigestsJob.perform_now(morning)

    emails = sent_emails
    assert_equal 1, emails.size
    _gateway, address, subject, body = emails.first
    assert_equal @alice.user.email, address
    assert_equal "Your Example Club update", subject
    assert_includes body, "<h1>November 17 Update for Alice Anderson</h1>"
    assert_includes body, "<h2>Tasks</h2><p>Two tasks for <b>A &amp; B</b></p>"
    assert_includes body, "<a href=\"https://example.com/tasks?a=1&amp;b=2\">Open Tasks</a>"
    assert_includes body, "<h2>Club &lt;news&gt;</h2><p>Something new</p>"

    since = Time.utc(2026, 11, 16, 13, 0)
    assert(@calls.all? { |_key, _person, given| given == since })
  end

  test "a person with nothing gets no email but is not asked again that day" do
    turn_on

    DeliverDailyDigestsJob.perform_now(morning)

    assert_equal [ @alice.user.email ], sent_emails.map(&:second)
    assert_not DigestDelivery.find_by(person: @bob).sent
    assert DigestDelivery.find_by(person: @alice).sent
  end

  test "daily sends at most once per person per day" do
    turn_on

    DeliverDailyDigestsJob.perform_now(morning)
    DeliverDailyDigestsJob.perform_now(morning + 15.minutes)

    assert_equal 1, sent_emails.size
    assert_equal 1, @calls.count { |key, person, _| key == :test_tasks && person == @alice }

    DeliverDailyDigestsJob.perform_now(morning + 1.day)
    assert_equal 2, sent_emails.size
  end

  test "daily waits for 7:00 in the site's time zone" do
    turn_on

    DeliverDailyDigestsJob.perform_now(morning - 45.minutes)
    assert_empty sent_emails

    DeliverDailyDigestsJob.perform_now(morning)
    assert_equal 1, sent_emails.size
  end

  test "daily goes out at 7:00 local time on the day the clocks change" do
    turn_on

    DeliverDailyDigestsJob.perform_now(Time.utc(2026, 11, 1, 12, 59))
    assert_empty sent_emails

    DeliverDailyDigestsJob.perform_now(Time.utc(2026, 11, 1, 13, 0))
    assert_equal 1, sent_emails.size
  end

  test "daily leaves out weekly and off sections" do
    turn_on
    @delivery[:test_tasks] = :off

    DeliverDailyDigestsJob.perform_now(morning)

    assert_empty sent_emails
    assert_empty @calls
  end

  test "daily skips a section that raises and sends the rest" do
    turn_on
    @delivery[:test_news] = :daily
    GatherPack::Digests.register(:test_tasks, label: "Tasks", delivery: -> { :daily }, build: ->(*) { raise "broken" })

    DeliverDailyDigestsJob.perform_now(morning)

    body = sent_emails.first.last
    assert_includes body, "Something new"
    assert_not_includes body, "Tasks"
  end

  test "weekly sections make the Infodump go out with no announcements" do
    turn_on

    infodump = Infodump.new(@alice)
    infodump.generate
    assert_enqueued_with(job: SendEmailJob) { infodump.send }

    body = sent_emails.first.last
    assert_includes body, "<h2>Club &lt;news&gt;</h2><p>Something new</p>"
    assert_not_includes body, "Two tasks"
    assert(@calls.all? { |_key, _person, since| since.between?(8.days.ago, 6.days.ago) })
  end

  test "the Infodump stays quiet for a person with nothing" do
    turn_on

    infodump = Infodump.new(@bob)
    infodump.generate
    assert_no_enqueued_jobs(only: SendEmailJob) { infodump.send }
  end

  test "both sends a section daily and in the Infodump" do
    turn_on
    @delivery[:test_tasks] = :both

    DeliverDailyDigestsJob.perform_now(morning)
    infodump = Infodump.new(@alice)
    infodump.generate
    infodump.send

    daily, weekly = sent_emails.map(&:last)
    assert_includes daily, "Two tasks"
    assert_includes weekly, "Two tasks"
    assert_includes weekly, "Something new"
  end

  test "off leaves a section out of the Infodump" do
    turn_on
    @delivery[:test_news] = :off

    infodump = Infodump.new(@alice)
    infodump.generate
    assert_no_enqueued_jobs(only: SendEmailJob) { infodump.send }
  end

  test "with the flag off nothing is sent or added" do
    DeliverDailyDigestsJob.perform_now(morning)
    infodump = Infodump.new(@alice)
    infodump.generate
    infodump.send

    assert_empty sent_emails
    assert_empty @calls
    assert_equal 0, DigestDelivery.count
  end

  test "old delivery records are pruned" do
    turn_on
    old = DigestDelivery.create!(person: @bob, delivered_on: Date.new(2026, 8, 1))

    DeliverDailyDigestsJob.perform_now(morning)

    assert_not DigestDelivery.exists?(old.id)
  end
end
