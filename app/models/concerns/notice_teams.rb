# The teams whose notices a person gets for their own team roles: those they
# manage and the teams below them. Unlike all_managed_teams, being an admin
# adds nothing.
module NoticeTeams
  extend ActiveSupport::Concern

  def notice_teams
    managed_team_ids = memberships.where(manager: true).pluck(:team_id)
    descendant_ids = Team.where(id: managed_team_ids).flat_map(&:all_descendant_ids)
    Team.where(id: managed_team_ids + descendant_ids)
  end
end
