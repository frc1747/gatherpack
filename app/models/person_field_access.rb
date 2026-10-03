# Decides what one viewer may do with one subject's person fields. Build one
# per (viewer, subject) pair: the relationship lookups behind each audience
# component run at most once, however many fields are checked.
class PersonFieldAccess
  attr_reader :viewer, :subject

  def initialize(viewer, subject)
    @viewer = viewer
    @subject = subject
  end

  def readable?(field)
    access(field, :read).present?
  end

  def writable?(field)
    access(field, :write).present?
  end

  # Why access is granted: :admin, an audience component (:subject,
  # :guardian, :leaders, :teammates, :everyone), or the granting Badge.
  # Returns nil when access is denied.
  def access(field, mode)
    return nil if viewer.nil? || subject.nil? || !applies?(field)
    return nil if mode == :write && field.system_read_only?
    return :admin if viewer.admin?

    level = mode == :read ? field.read_permission : field.write_permission
    PersonField::PERMISSION_LEVELS.fetch(level).find { |component| component?(component) } ||
      badge_grant(field, mode)&.badge
  end

  def applies?(field)
    field.team_id.nil? || subject_team_ids.include?(field.team_id)
  end

  def component?(component)
    case component
    when :subject then viewer.id == subject.id
    when :guardian then guardian?
    when :leaders then leader?
    when :teammates then teammate?
    when :everyone then true
    end
  end

  private

  def badge_grant(field, mode)
    field.person_field_badge_grants.find do |grant|
      (mode == :read || grant.write?) && viewer_badge_ids.include?(grant.badge_id) && grant.covers?(subject_team_ids)
    end
  end

  def guardian?
    return @guardian if defined?(@guardian)
    @guardian = subject.persisted? && subject.guardians.where(id: viewer.id).exists?
  end

  def leader?
    return @leader if defined?(@leader)
    @leader = viewer.can_manage(subject)
  end

  def teammate?
    return @teammate if defined?(@teammate)
    @teammate = (viewer.team_ids & subject.team_ids).any?
  end

  # The subject's direct teams plus their ancestors.
  def subject_team_ids
    @subject_team_ids ||= subject.all_ancestor_teams.ids
  end

  def viewer_badge_ids
    @viewer_badge_ids ||= viewer.badge_ids
  end
end
