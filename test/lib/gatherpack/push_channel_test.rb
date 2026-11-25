require "test_helper"
require "phone_notifications_test_support"

class GatherPack::PushChannelTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper
  include PhoneNotificationsTestSupport

  setup do
    use_throwaway_settings
    set_push_flag(true)
    @person = people(:one)
    @user = @person.user
    @gateway = create_push_gateway
    create_subscription(@user)
    enable_topics(@user, :announcements)
  end

  teardown { restore_settings }

  def deliver(person = @person, topic: :announcements, title: "Practice moved", path: "/announcements")
    GatherPack::PushChannel.deliver(person, topic: topic, title: title, path: path)
  end

  test "queues one job per subscription" do
    create_subscription(@user, endpoint: "#{ENDPOINT}-tablet")

    assert_enqueued_jobs 2, only: SendPushJob do
      deliver
    end
  end

  test "does nothing while the flag is off" do
    set_push_flag(false)

    assert_no_enqueued_jobs(only: SendPushJob) { deliver }
  end

  test "does nothing when the installable app is off" do
    Settings.set(:feature_installable_app, "false")

    assert_no_enqueued_jobs(only: SendPushJob) { deliver }
  end

  test "does nothing without a gateway" do
    @gateway.destroy!

    assert_nothing_raised do
      assert_no_enqueued_jobs(only: SendPushJob) { deliver }
    end
  end

  test "does nothing while the gateway has no keys yet" do
    @gateway.update!(public_key: nil, private_key: nil)

    assert_no_enqueued_jobs(only: SendPushJob) { deliver }
  end

  test "does nothing for a person with no login" do
    assert_no_enqueued_jobs(only: SendPushJob) { deliver(Person.new) }
  end

  test "does nothing when the topic isn't enabled for them" do
    enable_topics(@user)

    assert_no_enqueued_jobs(only: SendPushJob) { deliver }
  end

  test "does nothing for a topic nobody registered" do
    enable_topics(@user, :nonsense)

    assert_no_enqueued_jobs(only: SendPushJob) { deliver(topic: :nonsense) }
  end

  test "announcements stay off until someone chooses them" do
    @user.push_preference.destroy!
    @user.reload

    assert_no_enqueued_jobs(only: SendPushJob) { deliver }
  end

  test "refuses a path that isn't local" do
    [ "https://example.com/", "//example.com", "/\\example.com", "javascript:alert(1)", "announcements", "", nil, "/a b" ].each do |path|
      assert_raises(GatherPack::PushChannel::NonLocalPath, path.inspect) { deliver(path: path) }
    end
  end

  test "accepts a local path with a query" do
    assert_enqueued_jobs(1, only: SendPushJob) { deliver(path: "/announcements/ann_1?from=push") }
  end

  test "keeps a long title short enough for a payload" do
    assert_enqueued_with(job: SendPushJob, args: [ @gateway, @user.push_subscriptions.first, "#{"x" * 117}...", "/announcements" ]) do
      deliver(title: "x" * 500)
    end
  end
end
