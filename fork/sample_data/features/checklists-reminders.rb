# Sample data for feature/checklists-reminders.
#
# Medical Notes (a person field) is ticked "Keep out of email and
# notifications". Trip Eligibility gains an item that reads it, "Medical
# notes on file" (is filled in), so its Edit page's Reminders section says
# "Email: just "sign in", because it reads Medical Notes, which is kept out of
# email", and a reminder counts it ("1 more item. Sign in to see it.")
# instead of naming it. The checklist's own level stays Everything, so the
# other items show their name, status and summary.
#
# Trip Eligibility has scheduled reminders on: every 7 days, and 3 days
# before it ends, guardians too. One reminder is logged, sent by hand by
# Adam (admin) three days ago, so the section shows "Last reminder sent…".
# Nothing is emailed while loading. Open Trip Eligibility and press Send
# Reminder, then Preview for Kate: her email and her guardian's.
Hbr::SampleData.feature "feature/checklists-reminders" do |s|
  s.enable_feature :checklists
  s.enable_feature :person_fields
  s.enable_feature :checklist_reminders

  medical = PersonField.find_by!(key: "medical_notes")
  medical.update!(keep_out_of_email: true) unless medical.keep_out_of_email?
  # Chloe stays eligible (the checklists sample data expects it): she has notes.
  chloe = s.person("Chloe")
  chloe.set_field_value(medical, "No known conditions.") if chloe.field_value(medical).blank?

  checklist = Checklist.find_by!(title: "Trip Eligibility")
  item = ChecklistItem.find_or_initialize_by(checklist: checklist, label: "Medical notes on file")
  item.assign_attributes(kind: "person_field", position: 7)
  item.config_params = { field_id: medical.id, operator: "filled_in" }
  item.save! if item.new_record? || item.changed?

  checklist.update!(reminders_scheduled: true, reminder_every_days: 7, reminder_days_before_end: 3, reminder_guardians: true)
  unless checklist.checklist_reminders.exists?
    checklist.checklist_reminders.create!(sent_by: s.person("Adam"), sent_at: s.clock.days_from_now(-3, hour: 18),
      recipient_count: 6, guardian_count: 3)
  end

  Checklists::Refresher.new(checklist.reload, silent: true).call
  s.report "Trip Eligibility: \"Medical notes on file\" reads a field kept out of email; reminders every 7 days and 3 days before the end"
  s.expect("the medical notes item says only \"sign in\"") { Checklists::EmailLevel.for(item.reload) == "sign_in" }
  s.expect("the schedule is on") { Checklists::ReminderSchedule.new(checklist.reload).on? }
  s.expect("a reminder is logged") { checklist.checklist_reminders.exists? }
  s.expect("Chloe is still eligible") { checklist.checklist_results.find_by(person: chloe, item_id: nil)&.met? }
end
