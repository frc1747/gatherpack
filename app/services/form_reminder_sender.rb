# Emails the people who can act on a form for each subject still owing a
# complete response: the subject (if the respond level includes them) and
# their guardians (if it includes guardians). One email per recipient,
# listing each of their subjects.
class FormReminderSender
  include ERB::Util

  attr_reader :form, :subjects

  def initialize(form, subjects)
    @form = form
    @subjects = subjects
  end

  # { recipient Person => [subject Person, ...] }
  def recipients
    @recipients ||= subjects.each_with_object(Hash.new { |hash, key| hash[key] = [] }) do |subject, map|
      people = []
      people << subject if AudienceLevels.reaches?(form.respond_permission, :subject)
      people.concat(subject.guardians.to_a) if AudienceLevels.reaches?(form.respond_permission, :guardian)
      people.select { |person| person.user&.email.present? }.each { |person| map[person] << subject }
    end
  end

  def send!(sent_by:, filter: {})
    recipients.each do |recipient, recipient_subjects|
      SendEmailJob.perform_later(Gateway[:email_sending], recipient.user.email, email_subject, body(recipient, recipient_subjects))
    end
    FormResponse.where(form: form, subject_id: subjects.map(&:id)).update_all(last_reminded_at: Time.current)
    form.form_reminders.create!(sent_by: sent_by, sent_at: Time.current, recipient_count: recipients.size, filter: filter)
  end

  private

  def email_subject
    "#{Settings[:title]} - Reminder: #{form.title}"
  end

  def body(recipient, recipient_subjects)
    urls = Rails.application.routes.url_helpers
    due = form.closes_at ? " by #{form.closes_at.in_time_zone(Settings[:time_zone].presence || "UTC").strftime("%B %-d")}" : ""
    items = recipient_subjects.map do |subject|
      label = subject == recipient ? "You" : h(subject.display_name)
      "<li><a href=\"#{urls.edit_form_response_url(form, subject.id)}\">#{label}</a></li>"
    end
    "<p>Hi #{h(recipient.first_name)},</p>" \
      "<p>Please complete <strong>#{h(form.title)}</strong>#{due} for:</p><ul>#{items.join}</ul>"
  end
end
