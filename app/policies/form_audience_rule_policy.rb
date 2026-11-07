# Managers of a form change who it asks, but only among what they manage:
# teams within their managed teams, badges belonging to those teams, and
# people they lead. A form's creator (the creator badge) can also ask teams
# they belong to. Admins can target anything.
class FormAudienceRulePolicy < ApplicationPolicy
  def create?
    FormPolicy.new(user, record.form).manage? && targetable?
  end

  def destroy?
    FormPolicy.new(user, record.form).manage?
  end

  private

  def creator?
    record.form.run_by_creator?(person)
  end

  def targetable?
    return true if user.admin
    return false if record.target.nil?

    case record.target_type
    when "team" then person.all_managed_teams.where(id: record.team_id).exists? || (creator? && Form.creator_team_ids(person).include?(record.team_id))
    when "badge" then record.badge.team_id.present? && person.all_managed_teams.where(id: record.badge.team_id).exists?
    when "person" then person.all_managed_people.where(id: record.person_id).exists?
    end
  end
end
