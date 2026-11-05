# Answers which audience components (AudienceLevels) one viewer belongs to
# relative to one subject. Build one per (viewer, subject) pair: the
# relationship lookups behind each component run at most once, however many
# checks are made.
class AudienceAccess
  attr_reader :viewer, :subject

  def initialize(viewer, subject)
    @viewer = viewer
    @subject = subject
  end

  # The first component of the level the viewer belongs to, or nil. Admins
  # are not handled here; callers decide what admins may do.
  def level_component(level)
    AudienceLevels.components(level).find { |component| component?(component) }
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
