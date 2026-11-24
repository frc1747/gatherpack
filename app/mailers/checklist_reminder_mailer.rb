# Draws a checklist reminder from a Checklists::ReminderMessage payload
# (plain text and URLs, with the email levels already applied). Emails go
# out through the email gateway (SendEmailJob), like the app's other
# notices, so this only renders: render gives [subject, html body], and the
# preview shows the same body.
class ChecklistReminderMailer < ApplicationMailer
  layout false

  def self.render(payload)
    mail = reminder(payload).message
    [ mail.subject, mail.body.decoded ]
  end

  # The sections alone, for the summary email.
  def self.render_sections(sections)
    ApplicationController.render(partial: "checklist_reminder_mailer/sections", locals: { sections: sections })
  end

  def reminder(payload)
    @payload = payload
    mail(to: payload["to"], subject: payload["subject"])
  end
end
