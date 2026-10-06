# One person's (the subject's) record for one form: a numbered history of
# submissions, one of which may be active. Reports read the active one.
class FormResponse < ApplicationRecord
  has_neat_id :frmr
  include CanBeHooked
  has_paper_trail versions: { class_name: "AuditLog" }

  belongs_to :form
  belongs_to :subject, class_name: "Person"
  belongs_to :active_submission, class_name: "FormSubmission", optional: true
  has_many :form_submissions, -> { order(:number) }, dependent: :destroy, inverse_of: :form_response

  # A cached summary, recomputed by #sync_status!. "Not started" is the
  # absence of a response.
  enum :status, { draft: 0, waiting: 1, complete: 2, needs_reconfirmation: 3, withdrawn: 4 }, validate: true

  validates :subject_id, uniqueness: { scope: :form_id }

  def self.ransackable_attributes(auth_object = nil)
    [ "status", "subject_id", "updated_at" ]
  end

  def identifier_name
    "#{form&.title}: #{subject&.identifier_name}"
  end

  def identifier_icon
    "file-signature"
  end

  # The draft or pending submission, if any.
  def open_submission
    form_submissions.detect { |submission| submission.draft? || submission.pending? }
  end

  # The open submission, or a new draft started from the active one.
  def start_submission!(acting)
    open_submission || form_submissions.create!(
      number: (form_submissions.maximum(:number) || 0) + 1, status: :draft, form_version: form.content_version,
      based_on: active_submission, created_by: acting, answers: starting_answers
    ).tap { sync_status! }
  end

  # A new version starts from the active answers (or, after a withdrawal,
  # the withdrawn ones). Questions that update the profile start from the
  # profile, which is their source of truth; questions filled in from the
  # profile start there only the first time.
  def starting_answers
    previous = (active_submission || form_submissions.select(&:withdrawn?).max_by(&:number))&.answers || {}
    form.answerable_questions.each_with_object({}) do |question, answers|
      stored = if question.update_profile? || (question.prefill? && !previous.key?(question.key))
        question.store_answer(subject.field_value(question.person_field))
      else
        previous[question.key]
      end
      answers[question.key] = stored unless question.blank_answer?(stored)
    end
  end

  # Recomputes the status and runs the completed/incomplete hooks when the
  # response starts or stops being complete.
  def sync_status!
    form_submissions.reset
    was_complete = complete?
    self.status = computed_status
    self.update_in_progress = active_submission.present? && open_submission.present?
    save! if changed?

    if complete? && !was_complete
      run_domain_hooks("form_responses - completed")
    elsif was_complete && !complete?
      run_domain_hooks("form_responses - incomplete")
    end
  end

  private

  def computed_status
    if active_submission&.active?
      :complete
    elsif open_submission&.pending?
      :waiting
    elsif open_submission.nil? && form_submissions.any?(&:withdrawn?)
      :withdrawn
    else
      :draft
    end
  end

  def run_domain_hooks(event)
    Hook.where(event: event).each { |hook| hook.run(self) }
  end
end
