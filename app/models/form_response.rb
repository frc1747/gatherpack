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
  # absence of a response, or a response whose every version was discarded.
  enum :status, { draft: 0, waiting: 1, complete: 2, needs_reconfirmation: 3, withdrawn: 4, not_started: 5 }, validate: true

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

  # "Updates profile" questions whose profile value no longer matches what
  # the active submission signed.
  def profile_changes
    return [] unless active_submission
    form.answerable_questions.select { |question| active_submission.profile_changed?(question) }
  end

  # Why a response with an active submission needs re-confirmation: :form
  # (the form changed and asked for it) or :profile, or nil.
  def reconfirmation_reason
    return nil unless active_submission
    return :form if active_submission.form_version < form.reconfirm_from_version
    :profile if form.reconfirm_on_profile_change? && profile_changes.any?
  end

  # Recomputes the status, keeps the completion badge in step with it, and
  # runs the completed/incomplete hooks when the response starts or stops
  # being complete. The one place that grants or removes the badge.
  def sync_status!
    form_submissions.reset
    # Profile values may have just been written through another copy of
    # the subject.
    subject.reload if form.reconfirm_on_profile_change? && form.answerable_questions.any?(&:update_profile?)
    # From the database: a profile change during activation may already
    # have re-synced this response through another copy.
    was_complete = persisted? && FormResponse.where(id: id, status: :complete).exists?
    self.status = computed_status
    self.update_in_progress = active_submission.present? && open_submission.present?
    save! if changed?
    sync_completion_badge!

    if complete? && !was_complete
      run_domain_hooks("form_responses - completed")
    elsif was_complete && !complete?
      run_domain_hooks("form_responses - incomplete")
    end
  end

  private

  def computed_status
    if active_submission&.active?
      reconfirmation_reason ? :needs_reconfirmation : :complete
    elsif open_submission&.pending?
      :waiting
    elsif open_submission.nil? && form_submissions.any?(&:withdrawn?)
      :withdrawn
    elsif open_submission
      :draft
    else
      :not_started
    end
  end

  # A badge the subject can't hold (outside its team) is left off. Nothing
  # changes while Badges are turned off; the next sync after they're back
  # catches up.
  def sync_completion_badge!
    badge = form.completion_badge
    return unless badge && Form.badges_enabled?

    assignment = BadgeAssignment.find_by(badge: badge, person: subject)
    if complete? && assignment.nil?
      BadgeAssignment.create(badge: badge, person: subject)
    elsif !complete? && assignment
      assignment.destroy!
    end
  end

  def run_domain_hooks(event)
    Hook.where(event: event).each { |hook| hook.run(self) }
  end
end
