# A Northwind form with a deadline next week that reminds people who haven't
# answered 3 days before it, so the reminder goes out on its own.
Hbr::SampleData.feature "feature/forms-auto-reminders" do |s|
  s.enable_feature :forms
  s.enable_feature :forms_auto_reminders
  admin = s.login(:admin)
  youth = s.team(:youth)

  form = s.upsert!(Form, { key: "field_trip_permission" },
    created_by: admin, team: youth, status: "open", title: "Field Trip Permission",
    description: "Tell us if you can come.", closes_at: s.clock.days_from_now(7), auto_reminder_days: 3, auto_reminded_at: nil)
  FormAudienceRule.find_or_create_by!(form: form, effect: "include", target_type: "team", team: youth)

  s.report "Field Trip Permission: deadline in 7 days, reminds 3 days before"
  s.expect("the form will send an automatic reminder") { Form.find(form.id).auto_reminder_at.present? }
end
