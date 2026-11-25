# Draws an account reminder from an Accounting::ReminderMessage payload
# (plain text and URLs, with what each reminder may say already applied).
# Emails go out through the email gateway (SendEmailJob), like the app's
# other notices, so this only renders: render gives [subject, html body].
class AccountingMailer < ApplicationMailer
  layout false

  def self.render(payload)
    mail = reminder(payload).message
    [ mail.subject, mail.body.decoded ]
  end

  # The sections alone, for the summary email.
  def self.render_sections(sections)
    ApplicationController.render(partial: "accounting_mailer/sections", locals: { sections: sections })
  end

  def reminder(payload)
    @payload = payload
    mail(to: payload["to"], subject: payload["subject"])
  end
end
