require "test_helper"
require_relative "../support/checklist_reminders_world"

class ChecklistReminderMailerTest < ActiveSupport::TestCase
  include ChecklistRemindersWorld

  setup do
    build_checklists_world
    @checklist = create_world_checklist("Trip")
  end

  def email_for(name, checklist = @checklist, note: nil, **options)
    sender = Checklists::ReminderSender.new([ request_for(checklist, **options) ], note: note)
    message = sender.messages.find { |found| found.recipient.id == person(name).id }
    assert message, "no reminder for #{name}"
    ChecklistReminderMailer.render(message.payload)
  end

  test "Everything names the item and gives its status and summary" do
    with_reminders do
      add_item(@checklist, :badge, "Safety", { badge_ids: [ @safety.id ] })
      refresh(@checklist)

      subject, body = email_for(:member)
      assert_equal "#{Settings[:title]} - Reminder: Trip", subject
      assert_match "Hi Member,", body
      assert_match "Trip", body
      assert_match "<strong>Safety</strong>: Not Started", body
      assert_match "No Safety 2026", body
      assert_match "/people/#{person(:member).to_param}/checklists", body
    end
  end

  test "Name only gives the name and status, no summary" do
    with_reminders do
      add_item(@checklist, :badge, "Safety", { badge_ids: [ @safety.id ] }, email_level: "name_only")
      refresh(@checklist)

      _, body = email_for(:member)
      assert_match "<strong>Safety</strong>: Not Started", body
      assert_no_match "No Safety 2026", body
    end
  end

  test "Just sign in counts the item without naming it" do
    with_reminders do
      add_item(@checklist, :badge, "Safety", { badge_ids: [ @safety.id ] })
      add_item(@checklist, :badge, "Secret badge", { badge_ids: [ @viewer_badge.id ] }, email_level: "sign_in")
      refresh(@checklist)

      _, body = email_for(:member)
      assert_match "Safety", body
      assert_no_match "Secret badge", body
      assert_no_match "Report Viewer", body
      assert_match "1 more item. Sign in to see it.", body
    end
  end

  test "at the checklist's Just sign in neither the checklist nor any item is named" do
    with_reminders do
      @checklist.update!(email_level: "sign_in", title: "Academic Eligibility")
      add_item(@checklist, :badge, "Passing all classes", { badge_ids: [ @safety.id ] })
      refresh(@checklist)

      subject, body = email_for(:member)
      assert_equal "#{Settings[:title]} - Reminder: items to finish", subject
      assert_no_match "Academic", subject + body
      assert_no_match "Passing all classes", body
      assert_no_match "Safety 2026", body
      assert_match "You have items to finish in #{Settings[:title]}. Sign in to see them.", body
    end
  end

  test "a field kept out of email: its name and values never appear" do
    with_reminders do
      grades = create_field("Grade Point Average", :integer, keep_out_of_email: true, read_permission: "family")
      person(:member).set_field_value(grades, 1)
      add_item(@checklist, :person_field, "Passing all classes", { field_id: grades.id, operator: "at_least", number: 2 })
      add_item(@checklist, :badge, "Safety", { badge_ids: [ @safety.id ] })
      refresh(@checklist)

      subject, body = email_for(:member)
      [ "Grade Point Average", "grade point average", "Passing all classes", "at least 2", "Not: " ].each do |text|
        assert_no_match text, subject + body
      end
      assert_match "Safety", body
      assert_match "1 more item. Sign in to see it.", body
    end
  end

  test "the organizer's note goes above the list, as plain text" do
    with_reminders do
      add_item(@checklist, :badge, "Safety", { badge_ids: [ @safety.id ] })
      refresh(@checklist)

      _, body = email_for(:member, note: "Bring it <b>Friday</b>")
      assert_match "Bring it &lt;b&gt;Friday&lt;/b&gt;", body
      assert body.index("Friday") < body.index("Safety")
    end
  end

  test "the phone notification follows the same levels" do
    with_reminders do
      add_item(@checklist, :badge, "Safety", { badge_ids: [ @safety.id ] })
      refresh(@checklist)
      message = Checklists::ReminderSender.new([ request_for(@checklist) ]).messages.find { |found| found.recipient.id == person(:member).id }
      assert_equal "Reminder: Trip", message.push_title
      assert_equal "/people/#{person(:member).to_param}/checklists", message.push_path

      @checklist.update!(email_level: "sign_in")
      message = Checklists::ReminderSender.new([ request_for(@checklist.reload) ]).messages.find { |found| found.recipient.id == person(:member).id }
      assert_equal "Reminder: items to finish", message.push_title
    end
  end
end
