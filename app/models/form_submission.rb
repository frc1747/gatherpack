# One version of a response's answers. A draft becomes pending when
# submitted, and active once it has every required answer and signature.
# Activating supersedes the previous active version and writes "updates
# profile" answers to the profile. Answers never change after submission
# except by returning a pending submission to draft, which revokes its
# signatures. `content` records the form's text and questions as submitted,
# so what was signed can always be shown.
class FormSubmission < ApplicationRecord
  has_neat_id :frmsb
  include CanBeHooked
  has_paper_trail versions: { class_name: "AuditLog" }

  belongs_to :form_response, inverse_of: :form_submissions
  belongs_to :based_on, class_name: "FormSubmission", optional: true
  belongs_to :created_by, class_name: "Person", optional: true
  belongs_to :submitted_by, class_name: "Person", optional: true
  has_many :form_signatures, dependent: :destroy

  enum :status, { draft: 0, pending: 1, active: 2, superseded: 3, withdrawn: 4, discarded: 5 }, validate: true

  validates :number, presence: true, uniqueness: { scope: :form_response_id }

  def self.ransackable_attributes(auth_object = nil)
    [ "status", "number", "submitted_at", "activated_at" ]
  end

  def identifier_name
    "#{form_response&.identifier_name} ##{number}"
  end

  def identifier_icon
    "file-signature"
  end

  def form
    form_response.form
  end

  def subject
    form_response.subject
  end

  def open?
    draft? || pending?
  end

  def answer(question)
    question.cast_answer(answers[question.key])
  end

  def answered?(question)
    !question.blank_answer?(answers[question.key])
  end

  # Whether an "updates profile" answer no longer matches the profile. Only
  # questions that were on the form when this was submitted, and answers
  # that were copied to the profile, count.
  def profile_changed?(question)
    return false unless question.update_profile? && active?
    return false if profile_skipped.include?(question.key)
    return false if content["questions"].present? && content["questions"].none? { |snapshot| snapshot["key"] == question.key }

    normalize_compared(answer(question)) != normalize_compared(subject.field_value(question.person_field))
  end

  def standing_signatures
    form_signatures.select(&:standing?)
  end

  def signature_for(question)
    standing_signatures.detect { |signature| signature.form_question_id == question.id }
  end

  # Signature questions with no standing signature yet. Only a submitted
  # submission can be signed.
  def missing_signatures
    form.signature_questions.reject { |question| signature_for(question) }
  end

  # What's still needed before it can become active, in words, for "Waiting
  # for: …".
  def waiting_for
    missing_questions.map { |question| "an answer to #{question.label}" } +
      missing_signatures.map { |question| "#{question.signer_description}'s signature (#{question.label})" }
  end

  # The form's text and questions now, as stored in `content` on submit.
  def current_content
    {
      "version" => form.content_version, "title" => form.title, "description" => form.description,
      "questions" => form.form_questions.map(&:content_snapshot)
    }
  end

  # SHA-256 over the content and the answers. A signature stores it, so it
  # covers exactly what was submitted.
  def content_digest
    Digest::SHA256.hexdigest(JSON.generate([ content, answers.sort.to_h ]))
  end

  # Signs a signature question as `signer`, who must be allowed to
  # (`access.signing_role`). Returns an error message, or nil. The last
  # required signature activates the submission.
  def sign!(question, signer:, typed_name:, access:, ip_address: nil, user_agent: nil)
    return "This version isn't waiting for signatures." unless pending?
    return "This has already been signed." if signature_for(question)
    role = access.signing_role(question)
    return "You can't sign this." unless role
    return "Type your full name exactly as it appears on your account: #{signer.first_name} #{signer.last_name}." unless name_matches?(signer, typed_name)

    transaction do
      form_signatures.create!(form_question: question, signer: signer, signer_role: role, typed_name: typed_name.squish,
        signed_at: Time.current, content_digest: content_digest, ip_address: ip_address, user_agent: user_agent.to_s.first(500))
      form_signatures.reset
      ready? ? activate! : form_response.sync_status!
    end
    nil
  end

  # Applies input from the fill page for the questions `access` lets the
  # viewer write. Returns { key => error }. Changing a pending submission's
  # answers returns it to draft.
  def assign_answers(input, access)
    input = input.to_h.stringify_keys
    errors = {}
    updated = answers.dup
    form.answerable_questions.each do |question|
      next unless input.key?(question.key) && access.question_writable?(question)

      value, error = question.normalize_answer(input[question.key], current: answer(question))
      next errors[question.key] = error if error

      stored = question.store_answer(value)
      question.blank_answer?(stored) ? updated.delete(question.key) : updated[question.key] = stored
    end
    if updated != answers
      self.answers = updated
      if pending?
        self.status = :draft
        revoke_signatures!("Answers changed after signing", by: access.viewer)
      end
    end
    errors
  end

  # Required questions with no answer yet.
  def missing_questions
    form.answerable_questions.select { |question| question.required? && !answered?(question) }
  end

  # Submits for `acting`. Required questions the actor can answer must be
  # answered; others are left for someone who can, and the submission waits.
  # Returns { key => error } when it can't be submitted.
  def submit!(acting, access)
    errors = missing_questions.select { |question| access.question_writable?(question) }.to_h { |question| [ question.key, question.acknowledgment? ? "must be ticked" : "can't be blank" ] }
    return errors if errors.any?

    transaction do
      update!(status: :pending, submitted_by: acting, submitted_at: Time.current, form_version: form.content_version, content: current_content,
        entered_late: !form.open?)
      run_domain_hooks("form_submissions - submitted")
      ready? ? activate! : form_response.sync_status!
    end
    {}
  end

  # Ready to become active: every required question is answered and every
  # signature given.
  def ready?
    missing_questions.empty? && missing_signatures.empty?
  end

  def activate!
    transaction do
      previous = form_response.active_submission
      previous.update!(status: :superseded) if previous && previous != self
      update!(status: :active, activated_at: Time.current)
      form_response.update!(active_submission: self)
      apply_to_profile!
      run_domain_hooks("form_submissions - activated")
      form_response.sync_status!
    end
  end

  def withdraw!(by: nil)
    raise ArgumentError, "only the active submission can be withdrawn" unless active?

    transaction do
      update!(status: :withdrawn)
      revoke_signatures!("Withdrawn", by: by)
      form_response.update!(active_submission: nil)
      form_response.sync_status!
    end
  end

  def discard!(by: nil)
    raise ArgumentError, "only a draft or pending submission can be discarded" unless open?

    transaction do
      update!(status: :discarded)
      revoke_signatures!("Discarded", by: by)
      form_response.sync_status!
    end
  end

  # Moves a draft or pending submission to a new form content version. A
  # pending one goes back to draft, and its signatures are revoked, because
  # the text it was signed against changed.
  def move_to_version!(version)
    transaction do
      if pending?
        revoke_signatures!("The form changed after signing")
        update!(status: :draft, form_version: version)
        form_response.sync_status!
      else
        update!(form_version: version)
      end
    end
  end

  def revoke_signatures!(reason, by: nil)
    standing_signatures.each { |signature| signature.revoke!(reason, by: by) }
  end

  private

  def normalize_compared(value)
    case value
    when Array then value.sort
    when "" then nil
    else value
    end
  end

  # Case and spacing don't matter. The display name, or first and last name.
  def name_matches?(signer, typed_name)
    typed = typed_name.to_s.squish.downcase
    typed.present? && [ signer.display_name, "#{signer.first_name} #{signer.last_name}" ].compact.map { |name| name.squish.downcase }.include?(typed)
  end

  # Writes "updates profile" answers through the person field rules, as the
  # person who submitted. Fields they can't write (or that fail to save) are
  # recorded in profile_skipped and the profile is left alone.
  def apply_to_profile!
    questions = form.answerable_questions.select(&:update_profile?)
    return if questions.empty?

    access = PersonFieldAccess.new(submitted_by, subject)
    writable, skipped = questions.partition { |question| submitted_by && access.writable?(question.person_field) }
    values = writable.to_h { |question| [ question.person_field.key, profile_input(question) ] }
    failed = write_profile(values)
    if failed.any?
      # Save what can be saved; a field that fails validation is skipped.
      retry_values = values.except(*failed)
      failed = values.keys if retry_values.empty? || write_profile(retry_values).any?
      skipped += writable.select { |question| failed.include?(question.person_field.key) }
    end
    update_column(:profile_skipped, skipped.map(&:key).uniq)
  end

  # Returns the keys that failed to save: all of them if the profile can't be
  # saved for another reason.
  def write_profile(values)
    return [] if values.empty?

    person = Person.find(subject.id)
    person.assign_field_values(values, acting: submitted_by, only_given: true)
    return [] if person.save

    fields = PersonField.where(key: values.keys)
    failed = fields.select { |field| person.errors.key?(field.key.to_sym) || (field.system? && person.errors.key?(field.system_source.to_sym)) }.map(&:key)
    failed.presence || values.keys
  end

  # An answer as form input, as the profile edit form would post it.
  def profile_input(question)
    value = answer(question)
    case value
    when nil then ""
    when true then "1"
    when false then "0"
    when Date then value.iso8601
    when Array then value
    else value.to_s
    end
  end

  def run_domain_hooks(event)
    Hook.where(event: event).each { |hook| hook.run(self) }
  end
end
