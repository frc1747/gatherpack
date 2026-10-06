# Emails the people who can act on a form for each subject still owing a
# complete response: the subject (if the respond level includes them, or
# their signature is outstanding) and their guardians (likewise). One email per recipient,
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
      signers = outstanding_signers(subject)
      people = []
      people << subject if AudienceLevels.reaches?(form.respond_permission, :subject) || signers.include?(:subject)
      people.concat(subject.guardians.to_a) if AudienceLevels.reaches?(form.respond_permission, :guardian) || signers.include?(:guardian)
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

  # Who still has to sign a submitted response: :subject and/or :guardian.
  def outstanding_signers(subject)
    submission = form.response_for(subject)&.open_submission
    return [] unless submission&.pending?

    submission.missing_signatures.flat_map do |question|
      case question.signer
      when "subject" then [ :subject ]
      when "guardian" then [ :guardian ]
      when "guardian_if_minor" then subject.guardians.exists? ? [ :guardian ] : [ :subject ]
      else []
      end
    end.uniq
  end

  def email_subject
    "#{Settings[:title]} - Reminder: #{form.title}"
  end

  def body(recipient, recipient_subjects)
    urls = Rails.application.routes.url_helpers
    due = form.closes_at ? " by #{form.closes_at.in_time_zone(Settings[:time_zone].presence || "UTC").strftime("%B %-d")}" : ""
    items = recipient_subjects.map do |subject|
      label = subject == recipient ? "You" : h(subject.display_name)
      # A submitted response waiting for signatures is signed on its page.
      url = outstanding_signers(subject).any? ? urls.form_response_url(form, subject.id) : urls.edit_form_response_url(form, subject.id)
      "<li><a href=\"#{url}\">#{label}</a></li>"
    end
    "<p>Hi #{h(recipient.first_name)},</p>" \
      "<p>Please complete <strong>#{h(form.title)}</strong>#{due} for:</p><ul>#{items.join}</ul>"
  end
end
