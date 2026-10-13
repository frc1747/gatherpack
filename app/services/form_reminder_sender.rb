# Emails the people who can act on a form for each subject still owing a
# complete response: the subject (if the respond level includes them, or
# their signature is outstanding) and their guardians. One email per
# recipient, listing each of their subjects.
#
# Guardians who have to act (the subject can't respond, or a guardian's
# signature is outstanding) are always emailed. Guardians who would only be
# nudging a subject who can act themselves are emailed when
# include_guardians is on.
#
# Each email is "Hi {first name}," then a message, then the list of links.
# The message is Markdown with {first name}, {form} and {due} filled in;
# guardians get their own. A form keeps the messages last sent; nil means
# the default.
class FormReminderSender
  include ERB::Util

  DEFAULT_MESSAGE = "Please complete **{form}**{due} for:".freeze
  # Sends this large get a stronger warning before they go.
  LARGE_SEND = 25
  # Characters Redcarpet treats as Markdown, escaped in filled-in values.
  MARKDOWN_SPECIAL = /([\\`*_{}\[\]()#+\-.!|<>&~^=:])/

  attr_reader :form, :subjects, :include_guardians

  def initialize(form, subjects, include_guardians: true, message: nil, guardian_message: nil)
    @form = form
    @subjects = subjects
    @include_guardians = include_guardians
    @message = message
    @guardian_message = guardian_message
  end

  # { recipient Person => [subject Person, ...] }
  def recipients
    @recipients ||= subjects.each_with_object(Hash.new { |hash, key| hash[key] = [] }) do |subject, map|
      people = []
      people << subject if subject_acts?(subject)
      people.concat(guardians_of(subject)) if guardians_needed?(subject) || (include_guardians && guardians_respond?)
      people.select { |person| reachable?(person) }.uniq.each { |person| map[person] << subject }
    end
  end

  # A recipient is a guardian when they're reminded about anyone but
  # themselves.
  def guardian?(recipient)
    recipients.fetch(recipient, []).any? { |subject| subject != recipient }
  end

  def guardian_count
    recipients.keys.count { |recipient| guardian?(recipient) }
  end

  # Whether some guardians would only be nudging, so the sender can choose
  # whether to email them.
  def optional_guardians?
    guardians_respond? && subjects.any? { |subject| !guardians_needed?(subject) && guardians_of(subject).any? { |person| reachable?(person) } }
  end

  # Subjects nobody will be emailed about.
  def unreached
    reached = recipients.values.flatten.uniq
    subjects.reject { |subject| reached.include?(subject) }
  end

  def large?
    recipients.size >= LARGE_SEND
  end

  # The message in force: the one given, else the form's saved one, else
  # the default.
  def message
    self.class.clean(@message.nil? ? form.reminder_message : @message) || DEFAULT_MESSAGE
  end

  def guardian_message
    self.class.clean(@guardian_message.nil? ? form.guardian_reminder_message : @guardian_message) || DEFAULT_MESSAGE
  end

  # Line endings normalized and surrounding space removed; nil when blank.
  def self.clean(text)
    text.to_s.gsub("\r\n", "\n").strip.presence
  end

  # What to store on the form: nil for the default, so a changed default
  # still reaches forms that never customized it.
  def self.stored(text)
    cleaned = clean(text)
    cleaned unless cleaned == DEFAULT_MESSAGE
  end

  def send!(sent_by:, filter: {})
    recipients.each do |recipient, recipient_subjects|
      SendEmailJob.perform_later(Gateway[:email_sending], recipient.user.email, email_subject, body(recipient, recipient_subjects))
    end
    FormResponse.where(form: form, subject_id: subjects.map(&:id)).update_all(last_reminded_at: Time.current)
    form.form_reminders.create!(sent_by: sent_by, sent_at: Time.current, recipient_count: recipients.size,
      guardian_count: guardian_count, guardians_included: (include_guardians if optional_guardians?), filter: filter)
  end

  def email_subject
    "#{Settings[:title]} - Reminder: #{form.title}"
  end

  def body(recipient, recipient_subjects = recipients.fetch(recipient))
    urls = Rails.application.routes.url_helpers
    items = recipient_subjects.map do |subject|
      label = subject == recipient ? "You" : h(subject.display_name)
      # A submitted response waiting for signatures is signed on its page.
      url = outstanding_signers(subject).any? ? urls.form_response_url(form, subject.id) : urls.edit_form_response_url(form, subject.id)
      "<li><a href=\"#{url}\">#{label}</a></li>"
    end
    text = guardian?(recipient) ? guardian_message : message
    "<p>Hi #{h(recipient.first_name)},</p>#{render_message(text, recipient)}<ul>#{items.join}</ul>"
  end

  private

  def subject_acts?(subject)
    AudienceLevels.reaches?(form.respond_permission, :subject) || outstanding_signers(subject).include?(:subject)
  end

  # Guardians are the only ones who can act: the subject can't respond, or a
  # guardian's signature is outstanding.
  def guardians_needed?(subject)
    outstanding_signers(subject).include?(:guardian) ||
      (AudienceLevels.reaches?(form.respond_permission, :guardian) && !subject_acts?(subject))
  end

  def guardians_respond?
    AudienceLevels.reaches?(form.respond_permission, :guardian)
  end

  def guardians_of(subject)
    (@guardians ||= {})[subject.id] ||= subject.guardians.includes(:user).to_a
  end

  def reachable?(person)
    person.user&.email.present?
  end

  # Who still has to sign a submitted response: :subject and/or :guardian.
  def outstanding_signers(subject)
    (@signers ||= {})[subject.id] ||= begin
      submission = form.response_for(subject)&.open_submission
      if submission&.pending?
        submission.missing_signatures.flat_map { |question| FormAccess.signer_roles(question, subject) - [ :leader ] }.uniq
      else
        []
      end
    end
  end

  def render_message(text, recipient)
    values = { "{first name}" => recipient.first_name.to_s, "{form}" => form.title.to_s, "{due}" => due }
    filled = text.gsub(/\{first name\}|\{form\}|\{due\}/) { |placeholder| values.fetch(placeholder).gsub(MARKDOWN_SPECIAL) { "\\#{$1}" } }
    markdown = Redcarpet::Markdown.new(Redcarpet::Render::HTML, autolink: true, no_intra_emphasis: true, lax_spacing: true)
    ActionController::Base.helpers.sanitize(markdown.render(filled)).to_str.strip
  end

  def due
    form.closes_at ? " by #{form.closes_at.in_time_zone(Settings[:time_zone].presence || "UTC").strftime("%B %-d")}" : ""
  end
end
