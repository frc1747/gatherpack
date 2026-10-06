# Decides what one viewer may do with one subject's response to one form.
# The form's levels are relative to the subject, as person field levels are.
# Profile-backed questions also follow their person field's own levels, so
# keeping the answer on the form never widens who can see profile data.
#
# Holders of a granted badge (FormBadgeGrant) act as a leader of the people
# the grant covers: a read grant for seeing, a respond grant for filling in.
#
# People with a response who are no longer asked keep it: it stays readable
# at the same levels, and only their leaders can still enter a response.
#
# A form's creator who holds the form creator badge (Form.creator_badge)
# runs that form like an admin of its responses, and has no access to
# anything else about the people it asks.
class FormAccess < AudienceAccess
  attr_reader :form

  # Pass in_audience: (and has_response:) when already known, say from a
  # report that loaded the audience, to skip a query.
  def initialize(viewer, subject, form, in_audience: nil, has_response: nil)
    super(viewer, subject)
    @form = form
    @in_audience = in_audience unless in_audience.nil?
    @has_response = has_response unless has_response.nil?
  end

  def admin?
    viewer&.admin? || creator?
  end

  def creator?
    return @creator if defined?(@creator)
    @creator = form.run_by_creator?(viewer)
  end

  def in_audience?
    return @in_audience if defined?(@in_audience)
    @in_audience = subject.present? && form.in_audience?(subject)
  end

  def has_response?
    return @has_response if defined?(@has_response)
    @has_response = subject.present? && subject.persisted? && form.form_responses.where(subject: subject).exists?
  end

  # Has a response but is no longer asked.
  def former?
    !in_audience? && has_response?
  end

  def can_read?
    return false unless viewer && subject && reachable?
    admin? || level_component(form.read_permission).present? || grant(:read).present?
  end

  def can_respond?
    return false unless viewer && subject && reachable?
    return false unless admin? || level_component(form.respond_permission).present? || grant(:respond).present?
    in_audience? || subject_leader?
  end

  # A leader (or admin, or respond-grant holder) for this subject: may enter
  # late responses and record paper signatures.
  def subject_leader?
    admin? || component?(:leaders) || grant(:respond).present?
  end

  # Whether the viewer may start or change a submission now, given the
  # form's status and late-entry rule.
  def can_submit?
    return false unless can_respond?
    return true if form.open?
    form.closed? && form.late_entry_leaders? && subject_leader?
  end

  # Whether the viewer may start a new version after an earlier one. A
  # response that needs re-confirmation can always be updated while the
  # form takes submissions.
  def can_update?
    return false unless can_submit?
    form.allow_updates? || subject_leader? || response_needs_reconfirmation?
  end

  def question_readable?(question)
    return false unless can_read?
    return true unless question.answerable?
    return false unless admin? || reaches?(question.effective_read_permission, form.read_permission, :read)
    !question.profile_backed? || field_access.readable?(question.person_field)
  end

  def question_writable?(question)
    return false unless question.answerable? && can_respond? && question_readable?(question)
    return false unless admin? || reaches?(question.effective_write_permission, form.respond_permission, :respond)
    question.update_profile? ? field_access.writable?(question.person_field) : true
  end

  # Who may sign a signature question for this subject: :subject,
  # :guardian, and/or :leader (recording a paper signature).
  #
  # guardian_if_minor goes by age: someone of age (the guardianship age
  # limit, or 18 when none is set) signs for themselves, and an active
  # guardian still may; for a known minor only a guardian signs. With no
  # birthday on file, a guardian signs if there is one, otherwise the person.
  def self.signer_roles(question, subject)
    case question.signer
    when "subject" then [ :subject ]
    when "guardian" then [ :guardian ]
    when "leader" then [ :leader ]
    when "guardian_if_minor"
      case of_age?(subject)
      when true then [ :subject, :guardian ]
      when false then [ :guardian ]
      else subject.guardians.exists? ? [ :guardian ] : [ :subject ]
      end
    else []
    end
  end

  # true, false, or nil when the birthday isn't known.
  def self.of_age?(person)
    return nil unless person.birthday
    person.birthday <= Date.current - (Relationship.guardianship_age_limit || 18).years
  end

  # The role the viewer may sign this signature question in, or nil.
  def signing_role(question)
    return nil unless question.signature? && can_read?

    self.class.signer_roles(question, subject).find do |role|
      case role
      when :subject then self?
      when :guardian then component?(:guardian)
      when :leader then subject_leader? && can_respond?
      end
    end
  end

  def can_sign?(question)
    signing_role(question).present?
  end

  def field_access
    @field_access ||= PersonFieldAccess.new(viewer, subject)
  end

  private

  def self?
    viewer.id == subject.id
  end

  def reachable?
    in_audience? || has_response?
  end

  def response_needs_reconfirmation?
    form.form_responses.where(subject: subject, status: :needs_reconfirmation).exists?
  end

  # A question's level is reached by its own components, or by a grant
  # holder when the question has the form's level or one leaders reach.
  def reaches?(level, form_level, mode)
    return true if level_component(level)
    grant(mode).present? && (level.to_s == form_level.to_s || AudienceLevels.reaches?(level, :leaders))
  end

  # A grant the viewer holds that covers the subject. A respond grant also
  # covers reading.
  def grant(mode)
    @grants ||= {}
    return @grants[mode] if @grants.key?(mode)
    return @grants[mode] = nil unless Form.badges_enabled?

    @grants[mode] = form.form_badge_grants.find do |candidate|
      (mode == :read || candidate.respond?) && viewer_badge_ids.include?(candidate.badge_id) && candidate.covers?(subject_team_ids)
    end
  end
end
