require "test_helper"
require_relative "../support/checklist_reminders_world"

class ChecklistReminderScheduleTest < ActiveSupport::TestCase
  include ChecklistRemindersWorld

  setup do
    build_checklists_world
    @checklist = create_world_checklist("Trip", starts_on: Date.new(2026, 11, 1), ends_on: Date.new(2026, 11, 30))
  end

  def schedule
    Checklists::ReminderSchedule.new(@checklist.reload)
  end

  def sent_on(date)
    @checklist.checklist_reminders.create!(sent_at: Checklists.time_zone.local(date.year, date.month, date.day, 8), scheduled: true)
  end

  test "off by default, and a schedule needs a day" do
    assert_not schedule.due?(Date.new(2026, 11, 10))
    @checklist.reminders_scheduled = true
    assert_not @checklist.valid?
  end

  test "every N days from the last scheduled reminder, at most once a day" do
    @checklist.update!(reminders_scheduled: true, reminder_every_days: 7)
    assert schedule.due?(Date.new(2026, 11, 10))

    sent_on(Date.new(2026, 11, 10))
    assert_not schedule.due?(Date.new(2026, 11, 10))
    assert_not schedule.due?(Date.new(2026, 11, 16))
    assert schedule.due?(Date.new(2026, 11, 17))
    assert_equal Date.new(2026, 11, 17), schedule.next_on(Date.new(2026, 11, 11))
  end

  test "N days before the end, and never outside the checklist's dates" do
    @checklist.update!(reminders_scheduled: true, reminder_days_before_end: 3)
    assert_not schedule.due?(Date.new(2026, 11, 26))
    assert schedule.due?(Date.new(2026, 11, 27))
    assert_equal Date.new(2026, 11, 27), schedule.next_on(Date.new(2026, 11, 20))

    @checklist.update!(reminder_every_days: 1)
    assert_not schedule.due?(Date.new(2026, 10, 30))
    assert_not schedule.due?(Date.new(2026, 12, 1))
  end

  test "only active checklists" do
    @checklist.update!(reminders_scheduled: true, reminder_every_days: 1, status: :draft)
    assert_not schedule.due?(Date.new(2026, 11, 10))
    assert_empty Checklists::ReminderSchedule.due(on: Date.new(2026, 11, 10))
  end
end
