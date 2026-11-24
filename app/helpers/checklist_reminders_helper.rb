module ChecklistRemindersHelper
  # The schedule in words, for the Reminders section's state line:
  # "Reminders go every 7 days to people not complete, and 3 days before it
  # ends, guardians too. Next: 28 November 2026."
  def checklist_reminder_schedule_text(checklist)
    schedule = Checklists::ReminderSchedule.new(checklist)
    return "No scheduled reminders." unless schedule.on?

    whens = []
    whens << "every #{pluralize(checklist.reminder_every_days, "day")}" if checklist.reminder_every_days.to_i.positive?
    whens << "#{pluralize(checklist.reminder_days_before_end, "day")} before it ends" if checklist.reminder_days_before_end.to_i.positive?
    text = "Reminders go #{whens.join(", and ")} to people not #{checklist.word_for("met").downcase}"
    text += ", guardians too" if checklist.reminder_guardians?
    text += "."
    next_on = schedule.next_on
    if !checklist.active?
      text += " They start when the checklist is active."
    elsif next_on
      text += " Next: #{l(next_on, format: :long)}."
    end
    text
  end

  # "Last reminder sent 20 November 2026 by Organizer World to 12 people
  # (4 of them guardians)."
  def checklist_last_reminder_text(checklist)
    reminder = checklist.last_reminder
    return "No reminders sent yet." unless reminder

    by = reminder.scheduled? ? "on the schedule" : "by #{reminder.sent_by&.display_name || "someone"}"
    text = "Last reminder sent #{l(reminder.sent_at.in_time_zone(Checklists.time_zone).to_date, format: :long)} #{by} " \
      "to #{pluralize(reminder.recipient_count, "person")}"
    text += " (#{reminder.guardian_count} of them #{reminder.guardian_count == 1 ? "a guardian" : "guardians"})" if reminder.guardian_count.positive?
    "#{text}."
  end
end
