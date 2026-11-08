class CheckinFieldResponse < ApplicationRecord
  has_neat_id :cfr
  include CanBeHooked
  has_paper_trail versions: { class_name: "AuditLog" }
  belongs_to :checkin
  belongs_to :checkin_field

  before_save :keep_refused_response

  def permission_check(created_by)
    case checkin_field.permission
    when "added_by_admin"
      created_by.user.admin?
    when "added_by_manager"
      created_by.all_managed_teams.present? || created_by.user.admin?
    when "added_by_team_member"
      created_by.teams.present?
    when "added_by_participant"
      checkin.event.checkins.where(person: created_by).distinct.present? || created_by.user.admin?
    when "added_by_user"
      true
    end
  end

  private

  # Every write of a response, nested in a new or edited check-in or on its
  # own, stays with its field and is held to that field's permission for the person acting, which the
  # controller sets as the check-in's created_by. A refused value is dropped
  # and the response keeps what it had (nothing, on a new check-in). Writes
  # with no acting person (scripts, audit log reverts) aren't checked here.
  def keep_refused_response
    restore_attributes([ :checkin_field_id ]) if persisted?
    return unless response_changed?

    acting = checkin&.created_by
    self.response = response_was if acting && !permission_check(acting)
  end
end
