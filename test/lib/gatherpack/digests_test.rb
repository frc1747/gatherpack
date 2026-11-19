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
    GatherPack::Digests.unregister(:test_site)
    GatherPack::Digests.unregister(:badges)
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

  def choose(person, key, delivery)
    NoticePreference.create!(person: person, key: key.to_s, delivery: delivery.to_s)
  end

  def infodump_body(person)
    infodump = Infodump.new(person)
    infodump.generate
    infodump.send
    sent_emails.last&.last
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

  test "each is a site choice that leaves a section out of both summaries" do
    turn_on
    @delivery[:test_tasks] = :each
    @delivery[:test_news] = :each
    assert_equal :each, GatherPack::Digests[:test_tasks].delivery

    DeliverDailyDigestsJob.perform_now(morning)
    infodump = Infodump.new(@alice)
    infodump.generate
    infodump.send

    assert_empty sent_emails
    assert_empty @calls
  end

  test "delivery_for takes the person's own choice only while summaries are on" do
    choose(@alice, :test_tasks, :each)

    assert_equal :daily, GatherPack::Digests.delivery_for(:test_tasks, @alice)

    turn_on
    assert_equal :each, GatherPack::Digests.delivery_for(:test_tasks, @alice)
    assert_equal :daily, GatherPack::Digests.delivery_for(:test_tasks, @bob)
    assert_equal :weekly, GatherPack::Digests.delivery_for(:test_news, @alice)
  end

  test "delivery_for keeps the site's choice for a section people can't choose" do
    turn_on
    GatherPack::Digests.register(:test_site, label: "Site only", delivery: -> { :weekly }, build: ->(*) { }, personal: false)
    choose(@alice, :test_site, :each)

    assert_equal :weekly, GatherPack::Digests.delivery_for(:test_site, @alice)
    assert_not_includes GatherPack::Digests.personal_entries.map(&:key), :test_site
  end

  test "delivery_for is off for a section nobody registered" do
    turn_on

    assert_equal :off, GatherPack::Digests.delivery_for(:test_unknown, @alice)
  end

  test "sections registered without personal: are personal" do
    assert GatherPack::Digests[:test_tasks].personal
  end

  test "daily and weekly pick each person's sections by their own choice" do
    turn_on
    choose(@alice, :test_tasks, :weekly)
    choose(@alice, :test_news, :daily)

    DeliverDailyDigestsJob.perform_now(morning)
    daily = sent_emails.last.last
    assert_includes daily, "Something new"
    assert_not_includes daily, "Two tasks"

    weekly = infodump_body(@alice)
    assert_includes weekly, "Two tasks"
    assert_not_includes weekly, "Something new"
  end

  test "a person who chose each or off gets the section in neither summary" do
    turn_on
    choose(@alice, :test_tasks, :each)
    choose(@alice, :test_news, :off)

    DeliverDailyDigestsJob.perform_now(morning)
    infodump = Infodump.new(@alice)
    infodump.generate
    infodump.send

    assert_empty sent_emails
  end

  test "a person's daily choice sends the daily email when the site sends nothing daily" do
    turn_on
    @delivery[:test_tasks] = :weekly
    assert_not GatherPack::Digests.entries.any?(&:daily?)

    DeliverDailyDigestsJob.perform_now(morning)
    assert_empty sent_emails

    choose(@alice, :test_tasks, :daily)
    DeliverDailyDigestsJob.perform_now(morning + 1.day)
    assert_equal [ @alice.user.email ], sent_emails.map(&:second)
  end

  test "people choose only while summaries are on, and only for features that are on" do
    assert_empty GatherPack::Digests.personal_entries

    turn_on
    GatherPack::Digests.register(:badges, label: "Badges", delivery: -> { :daily }, build: ->(*) { })
    keys = %i[test_tasks test_news badges]
    assert_equal keys, GatherPack::Digests.personal_entries.map(&:key) & keys

    Settings[:feature_badges] = "false"
    assert_equal %i[test_tasks test_news], GatherPack::Digests.personal_entries.map(&:key) & keys
  end
end
