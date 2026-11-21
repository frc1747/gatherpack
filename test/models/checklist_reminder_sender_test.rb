require "test_helper"
require_relative "../support/checklist_reminders_world"

class ChecklistReminderSenderTest < ActiveSupport::TestCase
  include ChecklistRemindersWorld

  setup do
    build_checklists_world
    @checklist = create_world_checklist("Trip")
    @safety_item = add_item(@checklist, :badge, "Safety", { badge_ids: [ @safety.id ] })
  end

  def recipients(sender)
    sender.messages.map { |message| message.recipient.first_name }.sort
  end

  test "complete, exempt and excused people get nothing" do
    with_reminders do
      give_badge(:member, @safety)
      add_rule(@checklist, "exclude", "person", item: @safety_item, person_id: person(:rookie).id)
      ChecklistExcuse.create!(item: @safety_item, person: person(:member2), reason: "Away", created_by: person(:club_manager))
      refresh(@checklist)

      names = recipients(Checklists::ReminderSender.new([ request_for(@checklist) ]))
      assert_includes names, "Kid"
      assert_not_includes names, "Member"
      assert_not_includes names, "MemberTwo"
      assert_not_includes names, "Rookie"
    end
  end

  test "guardians only when ticked, about their ward" do
    with_reminders do
      refresh(@checklist)

      assert_not_includes recipients(Checklists::ReminderSender.new([ request_for(@checklist) ])), "Parent"

      sender = Checklists::ReminderSender.new([ request_for(@checklist, guardians: true) ])
      message = sender.messages.find { |found| found.recipient.id == person(:parent).id }
      assert message
      assert_equal [ person(:kid).id ], message.subjects.map(&:id)
      _, body = ChecklistReminderMailer.render(message.payload)
      assert_match "Trip: Kid World", body
      assert_equal 1, sender.guardian_count(@checklist)
    end
  end

  test "guardians don't get items they can't see" do
    with_reminders do
      add_item(@checklist, :has_login, "Private", {}, read_level: "self_and_leaders")
      add_item(@checklist, :badge, "Medical", { badge_ids: [ @viewer_badge.id ] }, read_level: "self_and_leaders")
      refresh(@checklist)

      sender = Checklists::ReminderSender.new([ request_for(@checklist, guardians: true) ])
      parent = sender.messages.find { |found| found.recipient.id == person(:parent).id }
      kid = sender.messages.find { |found| found.recipient.id == person(:kid).id }
      assert_equal [ "Safety" ], parent.entries.first.lines.map { |line| line.item.label }
      assert_equal [ "Safety", "Medical" ], kid.entries.first.lines.map { |line| line.item.label }
    end
  end

  test "a guardian with two wards on the checklist gets one email" do
    with_reminders do
      Relationship.create!(parent: person(:parent), child: person(:rookie), relationship_type: @parent_of, created_by: person(:admin))
      refresh(@checklist)

      perform_enqueued_jobs(only: []) do
        Checklists::ReminderSender.new([ request_for(@checklist, guardians: true) ]).send!
      end
      parent_emails = emails_to(:parent)
      assert_equal 1, parent_emails.size
      assert_match "Trip: Kid World", parent_emails.first[2]
      assert_match "Trip: Rookie World", parent_emails.first[2]
    end
  end

  test "only the people ticked, when some are" do
    with_reminders do
      refresh(@checklist)
      sender = Checklists::ReminderSender.new([ request_for(@checklist, person_ids: [ person(:kid).id ]) ])
      assert_equal [ "Kid" ], recipients(sender)
    end
  end

  test "each send is recorded with counts only, and runs its hooks" do
    with_reminders do
      refresh(@checklist)
      Hook.create!(name: "Count reminders", event: ChecklistReminder::CREATED_EVENT, code: "Thread.current[:reminder_hook] = model.recipient_count")

      reminders = Checklists::ReminderSender.new([ request_for(@checklist, guardians: true) ], by: person(:organizer)).send!
      reminder = reminders.first
      assert_equal person(:organizer), reminder.sent_by
      assert_not reminder.scheduled?
      assert_equal sent_emails.size, reminder.recipient_count
      assert_equal 1, reminder.guardian_count
      assert_equal reminder.recipient_count, Thread.current[:reminder_hook]
      assert_equal %w[checklist_id created_at guardian_count id recipient_count scheduled sent_at sent_by_id updated_at], ChecklistReminder.column_names.sort
    ensure
      Thread.current[:reminder_hook] = nil
    end
  end

  test "the daily job sends one email per person across checklists, and once a day" do
    with_reminders do
      @checklist.update!(reminders_scheduled: true, reminder_every_days: 7)
      second = create_world_checklist("Camp", reminders_scheduled: true, reminder_every_days: 3)
      add_item(second, :badge, "Medical", { badge_ids: [ @viewer_badge.id ] })
      refresh(@checklist)
      refresh(second)

      ChecklistReminderJob.perform_now
      kid_emails = emails_to(:kid)
      assert_equal 1, kid_emails.size
      assert_equal "#{Settings[:title]} - Reminder: items to finish", kid_emails.first[1]
      assert_match "Trip", kid_emails.first[2]
      assert_match "Camp", kid_emails.first[2]
      assert_equal 2, ChecklistReminder.scheduled.count

      clear_enqueued_jobs
      ChecklistReminderJob.perform_now
      assert_empty sent_emails
    end
  end

  test "the job does nothing while reminders are off" do
    with_settings(feature_checklists: "true", feature_checklist_reminders: "false") do
      @checklist.update!(reminders_scheduled: true, reminder_every_days: 1)
      refresh(@checklist)
      ChecklistReminderJob.perform_now
      assert_empty sent_emails
      assert_equal 0, ChecklistReminder.count
    end
  end

  test "through the summary: people who chose it get no email, and see it in their section" do
    with_reminders do
      @checklist.update!(reminders_scheduled: true, reminder_every_days: 7, reminder_via_digest: true)
      refresh(@checklist)

      with_digest_delivery(:daily) do
        Checklists::ReminderSender.new([ request_for(@checklist) ], scheduled: true).send!
        assert_empty sent_emails
        assert ChecklistReminder.last.recipient_count.positive?

        html = Checklists::ReminderDigest.html_for(person(:kid), since: 1.day.ago)
        assert_match "Safety", html
        assert_nil Checklists::ReminderDigest.html_for(person(:parent), since: 1.day.ago)
      end

      with_digest_delivery(:off) do
        Checklists::ReminderSender.new([ request_for(@checklist) ], scheduled: true).send!
        assert_empty sent_emails
      end

      # By hand it's always an email.
      with_digest_delivery(:daily) do
        Checklists::ReminderSender.new([ request_for(@checklist) ]).send!
        assert_not_empty emails_to(:kid)
      end
    end
  end

  test "without the summaries seam every reminder is an email" do
    skip "the summaries seam is merged here" if Checklists::ReminderDigest.available?

    assert_equal :each, Checklists::ReminderDigest.delivery_for(person(:kid))
  end
end
