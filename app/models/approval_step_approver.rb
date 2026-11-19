# Who approves on an ApprovalStep, one grant row (Orders::Reach): holders of
# a badge (kind badge), the managers of a team (team_managers, manager_team)
# or the managers of the request's own team (own_team_managers), for a team
# and the teams below it, or for every team when team is blank. A row for
# the request's own team takes no team. Only badges admins assign count.
class ApprovalStepApprover < ApplicationRecord
  has_neat_id :apsa
  has_paper_trail versions: { class_name: "AuditLog" }

  enum :kind, { badge: "badge", team_managers: "team_managers", own_team_managers: "own_team_managers" },
    default: "badge", validate: true

  belongs_to :approval_step, inverse_of: :approvers
  belongs_to :badge, optional: true
  belongs_to :manager_team, class_name: "Team", optional: true
  belongs_to :team, optional: true

  before_validation :clear_unused_columns
  validates :badge, presence: true, if: :badge?
  validates :manager_team, presence: true, if: :team_managers?
  validates :kind, uniqueness: { scope: %i[approval_step_id badge_id manager_team_id team_id] }

  # The setting line for the row: "Badge > Team", "Managers of Team > Team"
  # or "Managers of each team"; the team left out for every team.
  def line
    Orders::Reach.format_line(kind, badge? ? badge&.name : manager_team&.name, team&.name)
  end

  # How the row reads in the list of steps: "Mentor (for Robotics)",
  # "managers of Finance (every team)", "managers of each team".
  def label
    return "managers of each team" if own_team_managers?

    who = badge? ? badge&.name : "managers of #{manager_team&.name}"
    "#{who} (#{team ? "for #{team.name}" : "every team"})"
  end

  # The row as Orders::Reach reads it.
  def reach_row
    Orders::Reach::Row.new(kind: kind.to_sym, badge: badge, manager_team: manager_team, team: own_team_managers? ? nil : team)
  end

  # What a row fills in on the form, so blank new rows can be left out.
  def self.blank_attributes?(attributes)
    return false if attributes[:id].present?

    case attributes[:kind].presence || "badge"
    when "badge" then attributes[:badge_id].blank?
    when "team_managers" then attributes[:manager_team_id].blank?
    else false
    end
  end

  private

  def clear_unused_columns
    self.badge = nil unless badge?
    self.manager_team = nil unless team_managers?
    self.team = nil if own_team_managers?
  end
end
