# Decides what one viewer may do with one subject's response to one form.
# The form's levels are relative to the subject, as person field levels are.
# Profile-backed questions also follow their person field's own levels, so
# keeping the answer on the form never widens who can see profile data.
class FormAccess < AudienceAccess
  attr_reader :form

  # Pass in_audience: true when the subject is already known to be in the
  # form's audience (say, from Form#readable_subjects_for), to skip a query.
  def initialize(viewer, subject, form, in_audience: nil)
    super(viewer, subject)
    @form = form
    @in_audience = in_audience unless in_audience.nil?
  end

  def admin?
    viewer&.admin? || false
  end

  def in_audience?
    return @in_audience if defined?(@in_audience)
    @in_audience = subject.present? && form.in_audience?(subject)
  end

  def can_read?
    return false unless viewer && subject && in_audience?
    admin? || level_component(form.read_permission).present?
  end

  def can_respond?
    return false unless viewer && subject && in_audience?
    admin? || level_component(form.respond_permission).present?
  end

  # A leader (or admin) for this subject: may enter late responses.
  def subject_leader?
    admin? || component?(:leaders)
  end

  # Whether the viewer may start or change a submission now, given the
  # form's status and late-entry rule.
  def can_submit?
    return false unless can_respond?
    return true if form.open?
    form.closed? && form.late_entry_leaders? && subject_leader?
  end

  # Whether the viewer may start a new version after an earlier one.
  def can_update?
    can_submit? && (form.allow_updates? || subject_leader?)
  end

  def question_readable?(question)
    return false unless can_read?
    return true unless question.answerable?
    return false unless admin? || level_component(question.effective_read_permission)
    !question.profile_backed? || field_access.readable?(question.person_field)
  end

  def question_writable?(question)
    return false unless question.answerable? && can_respond? && question_readable?(question)
    return false unless admin? || level_component(question.effective_write_permission)
    question.update_profile? ? field_access.writable?(question.person_field) : true
  end

  def field_access
    @field_access ||= PersonFieldAccess.new(viewer, subject)
  end
end
