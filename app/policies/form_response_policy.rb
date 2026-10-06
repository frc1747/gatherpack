# Access to one subject's response, from the form's levels (FormAccess). The
# record may be an unsaved response for someone who hasn't started.
class FormResponsePolicy < ApplicationPolicy
  def show?
    access.can_read?
  end

  # Filling in, or updating submitted answers. An update only creates a
  # draft when it's saved, so opening the form and cancelling changes nothing.
  def edit?
    updating? ? access.can_update? : access.can_submit?
  end

  def update?
    edit?
  end

  def submit?
    access.can_submit? && record.open_submission.present?
  end

  def start_update?
    updating? && access.can_update?
  end

  def discard?
    submission = record.open_submission
    access.can_respond? && submission.present? && (submission.created_by_id == person.id || access.subject_leader?)
  end

  # Not while an update is in progress, so it's never unclear which version
  # a withdrawal applies to.
  def withdraw?
    access.can_respond? && record.active_submission.present? && record.open_submission.nil?
  end

  def access
    @access ||= FormAccess.new(person, record.subject, record.form)
  end

  private

  def updating?
    record.active_submission.present? && record.open_submission.nil?
  end
end
