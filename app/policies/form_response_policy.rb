# Access to one subject's response, from the form's levels (FormAccess). The
# record may be an unsaved response for someone who hasn't started.
class FormResponsePolicy < ApplicationPolicy
  def show?
    access.can_read?
  end

  def edit?
    access.can_submit?
  end

  # Saving answers needs a draft or pending submission, or nothing yet. A
  # complete response is changed by starting an update first.
  def update?
    access.can_submit? && (record.open_submission.present? || record.active_submission.nil?)
  end

  def submit?
    access.can_submit? && record.open_submission.present?
  end

  def start_update?
    access.can_update? && record.active_submission.present? && record.open_submission.nil?
  end

  def discard?
    submission = record.open_submission
    access.can_respond? && submission.present? && (submission.created_by_id == person.id || access.subject_leader?)
  end

  def withdraw?
    access.can_respond? && record.active_submission.present?
  end

  def access
    @access ||= FormAccess.new(person, record.subject, record.form)
  end
end
