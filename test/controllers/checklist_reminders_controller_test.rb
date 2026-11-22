require "test_helper"
require_relative "../support/checklist_reminders_world"

class ChecklistRemindersControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include ChecklistRemindersWorld

  setup do
    host! "localhost"
    build_checklists_world
    @checklist = create_world_checklist("Trip")
    add_rule(@checklist, :include, :team, team_id: @members.id)
    @safety_item = add_item(@checklist, :badge, "Safety", { badge_ids: [ @safety.id ] })
    give_badge(:member, @safety)
    refresh(@checklist)
  end

  test "with reminders off: no button, no Reminders section, the pages send people away" do
    with_settings(feature_checklists: "true", feature_checklist_reminders: "false") do
      sign_in person(:club_manager).user
      get checklist_path(@checklist)
      assert_response :success
      assert_no_match "Send Reminder", response.body

      get edit_checklist_path(@checklist, tab: "reminders")
      assert_response :success
      assert_no_match "Scheduled reminders", response.body

      get new_checklist_checklist_reminder_path(@checklist)
      assert_redirected_to root_path
      post checklist_checklist_reminders_path(@checklist), params: { reminder: { who: "everyone" } }
      assert_redirected_to root_path
      patch checklist_checklist_reminder_settings_path(@checklist), params: { checklist: { reminders_scheduled: "1", reminder_every_days: 1 } }
      assert_redirected_to root_path
      assert_not @checklist.reload.reminders_scheduled?
      assert_empty sent_emails
    end
  end

  test "whoever runs the checklist gets Send Reminder; others don't" do
    with_reminders do
      sign_in person(:club_manager).user
      get checklist_path(@checklist)
      assert_select "a.btn-primary", "Send Reminder"
      get new_checklist_checklist_reminder_path(@checklist)
      assert_response :success
      assert_match "Everyone not complete (3)", response.body

      sign_in person(:member).user
      get checklist_path(@checklist)
      assert_no_match "Send Reminder", response.body
      get new_checklist_checklist_reminder_path(@checklist)
      assert_response :redirect
      post checklist_checklist_reminders_path(@checklist), params: { reminder: { who: "everyone" } }
      assert_empty sent_emails
    end
  end

  test "a draft can't be reminded, but its Reminders section can be set up" do
    with_reminders do
      @checklist.update!(status: :draft)
      sign_in person(:club_manager).user

      get checklist_path(@checklist)
      assert_response :success
      assert_no_match "Send Reminder", response.body
      get new_checklist_checklist_reminder_path(@checklist)
      assert_response :redirect
      post checklist_checklist_reminders_path(@checklist), params: { reminder: { who: "everyone" }, send: "1" }
      assert_response :redirect
      assert_empty sent_emails
      assert_equal 0, ChecklistReminder.count

      get edit_checklist_path(@checklist, tab: "reminders")
      assert_match "Scheduled reminders", response.body
      patch checklist_checklist_reminder_settings_path(@checklist), params: { checklist: { email_level: "name_only" } }
      assert_equal "name_only", @checklist.reload.email_level
    end
  end

  test "the preview is exactly what's sent, for the person and their guardian" do
    with_reminders do
      sign_in person(:club_manager).user
      params = { reminder: { who: "everyone", guardians: "1", note: "Before the trip, please" }, preview_person_id: person(:kid).id }

      post checklist_checklist_reminders_path(@checklist), params: params.merge(preview: "1")
      assert_response :unprocessable_entity
      preview = response.body
      assert_empty sent_emails
      assert_match "To Kid World", preview
      assert_match "To Parent World", preview

      post checklist_checklist_reminders_path(@checklist), params: params.merge(send: "1")
      assert_redirected_to checklist_path(@checklist)
      kid = emails_to(:kid).sole
      parent = emails_to(:parent).sole
      assert_includes preview, kid[2]
      assert_includes preview, parent[2]
      assert_includes preview, ERB::Util.h(kid[1])
      assert_match "Before the trip, please", kid[2]

      reminder = ChecklistReminder.sole
      assert_equal person(:club_manager), reminder.sent_by
      assert_equal 1, reminder.guardian_count
      assert_equal "Reminder sent to #{reminder.recipient_count} people (1 of them a guardian).", flash[:notice]
    end
  end

  test "only the people ticked, when that's chosen" do
    with_reminders do
      sign_in person(:club_manager).user
      post checklist_checklist_reminders_path(@checklist),
        params: { reminder: { who: "ticked", person_ids: [ person(:rookie).id, person(:member).id ] }, send: "1" }
      assert_equal [ person(:rookie).user.email ], sent_emails.map(&:first)
    end
  end

  test "Reminders section: what reminders may say and the schedule are saved" do
    with_reminders do
      grades = create_field("Grade Point Average", :integer, keep_out_of_email: true)
      grades_item = add_item(@checklist, :person_field, "Passing all classes", { field_id: grades.id, operator: "at_least", number: 2 })
      sign_in person(:club_manager).user

      get edit_checklist_path(@checklist, tab: "reminders")
      assert_match "Email: just &quot;sign in&quot;, because it reads Grade Point Average, which is kept out of email", response.body
      assert_match "No scheduled reminders.", response.body
      assert_match "No reminders sent yet.", response.body

      patch checklist_checklist_reminder_settings_path(@checklist), params: {
        checklist: { email_level: "name_only", reminders_scheduled: "1", reminder_every_days: "7", reminder_guardians: "1" },
        item_levels: { @safety_item.id => "sign_in", grades_item.id => "" }
      }
      assert_redirected_to edit_checklist_path(@checklist, tab: "reminders")
      @checklist.reload
      assert_equal "name_only", @checklist.email_level
      assert_equal 7, @checklist.reminder_every_days
      assert @checklist.reminder_guardians?
      assert_equal "sign_in", @safety_item.reload.email_level

      get edit_checklist_path(@checklist, tab: "reminders")
      assert_match "Reminders go every 7 days to people not complete, guardians too.", response.body

      patch checklist_checklist_reminder_settings_path(@checklist), params: { checklist: { reminders_scheduled: "1", reminder_every_days: "" } }
      assert_match "Say how often", flash[:alert]
      assert_equal 7, @checklist.reload.reminder_every_days
    end
  end
end
