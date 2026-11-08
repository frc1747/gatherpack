require "test_helper"
require "phone_notifications_test_support"

class AnnouncementPushConnectorTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper
  include PhoneNotificationsTestSupport

  setup do
    use_throwaway_settings
    set_push_flag(true)
    create_push_gateway
    @user = users(:one)
    @user.update_column(:email, "someone@example.com") if @user.email.blank?
    create_subscription(@user)
    enable_topics(@user, :announcements)
    @announcement = Announcement.create!(title: "Practice moved", content: "Details", start_time: 1.hour.ago, end_time: 1.day.from_now, notify_now: "1")
  end

  teardown { restore_settings }

  def run_router
    AnnouncementNotificationRouter.new(@announcement).run
  end

  test "sends one push per enabled recipient" do
    assert_enqueued_jobs(1, only: SendPushJob) { run_router }
  end

  test "opens the announcement" do
    assert_enqueued_with(job: SendPushJob, args: [ Gateway[:push_sending], @user.push_subscriptions.first, "Practice moved", "/announcements/#{@announcement.to_param}" ]) { run_router }
  end

  test "sends nothing unless the leader chose to notify people" do
    @announcement.notify_now = "0"

    assert_no_enqueued_jobs(only: SendPushJob) { run_router }
  end

  test "sends nothing with the flag off, and the email still goes" do
    set_push_flag(false)

    assert_no_enqueued_jobs(only: SendPushJob) do
      assert_enqueued_jobs(Person.joins(:user).count, only: SendEmailJob) { run_router }
    end
  end

  test "email still goes out when push fails" do
    replacing(GatherPack::PushChannel, :deliver, ->(*, **) { raise "push is down" }) do
      assert_enqueued_jobs(Person.joins(:user).count, only: SendEmailJob) do
        assert_nothing_raised { run_router }
      end
    end
  end
end
