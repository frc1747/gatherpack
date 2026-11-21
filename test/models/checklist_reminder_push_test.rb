require "test_helper"
require_relative "../support/checklist_reminders_world"

# The phone notification that follows each reminder email, with
# GatherPack::PushChannel stubbed (it exists only where the phone
# notifications seam is merged).
class ChecklistReminderPushTest < ActiveSupport::TestCase
  include ChecklistRemindersWorld

  module FakePushChannel
    class << self
      attr_accessor :sent, :available, :failing

      def available? = available

      def deliver(person, topic:, title:, path:)
        raise "push service down" if failing

        sent << { person: person, topic: topic, title: title, path: path }
      end
    end
  end

  setup do
    build_checklists_world
    @checklist = create_world_checklist("Trip")
    add_item(@checklist, :badge, "Safety", { badge_ids: [ @safety.id ] })
    @original = GatherPack.send(:remove_const, :PushChannel) if GatherPack.const_defined?(:PushChannel, false)
    GatherPack.const_set(:PushChannel, FakePushChannel)
    FakePushChannel.sent = []
    FakePushChannel.available = true
    FakePushChannel.failing = false
    # Where the phone notifications seam is merged, the initializer has
    # already prepended the connector to ReminderSender itself.
    @sender_class =
      if Checklists::ReminderSender.ancestors.include?(Checklists::ReminderPushConnector)
        Checklists::ReminderSender
      else
        Class.new(Checklists::ReminderSender) { prepend Checklists::ReminderPushConnector }
      end
  end

  teardown do
    GatherPack.send(:remove_const, :PushChannel)
    GatherPack.const_set(:PushChannel, @original) if @original
  end

  def send_reminders(guardians: false)
    refresh(@checklist)
    @sender_class.new([ request_for(@checklist.reload, guardians: guardians) ]).send!
  end

  test "each email is followed by a notification on the Checklists topic, with the same levels" do
    with_reminders do
      send_reminders(guardians: true)
      kid = FakePushChannel.sent.find { |push| push[:person] == person(:kid) }
      assert_equal :checklists, kid[:topic]
      assert_equal "Reminder: Trip", kid[:title]
      assert_equal "/people/#{person(:kid).to_param}/checklists", kid[:path]
      assert_equal sent_emails.size, FakePushChannel.sent.size

      parent = FakePushChannel.sent.find { |push| push[:person] == person(:parent) }
      assert_no_match "Kid", parent[:title]

      FakePushChannel.sent = []
      clear_enqueued_jobs
      @checklist.update!(email_level: "sign_in")
      send_reminders
      assert FakePushChannel.sent.any?
      assert FakePushChannel.sent.all? { |push| push[:title] == "Reminder: items to finish" }
    end
  end

  test "nothing goes to phones while notifications aren't available, and the emails still go" do
    with_reminders do
      FakePushChannel.available = false
      send_reminders
      assert_empty FakePushChannel.sent
      assert_not_empty sent_emails
    end
  end

  test "a failing notification can't stop the emails" do
    with_reminders do
      FakePushChannel.failing = true
      send_reminders
      assert_not_empty sent_emails
    end
  end
end
