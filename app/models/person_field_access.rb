# Decides what one viewer may do with one subject's person fields. Build one
# per (viewer, subject) pair: the relationship lookups behind each audience
# component run at most once, however many fields are checked.
class PersonFieldAccess < AudienceAccess
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

    level_component(mode == :read ? field.read_permission : field.write_permission) ||
      badge_grant(field, mode)&.badge
  end

  def applies?(field)
    field.team_id.nil? || subject_team_ids.include?(field.team_id)
  end

  private

  def badge_grant(field, mode)
    field.person_field_badge_grants.find do |grant|
      (mode == :read || grant.write?) && viewer_badge_ids.include?(grant.badge_id) && grant.covers?(subject_team_ids)
    end
  end
end
