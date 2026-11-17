class BadgeAssignment < ApplicationRecord
  has_neat_id :bda
  include CanBeHooked
  has_paper_trail versions: { class_name: "AuditLog" }
  belongs_to :badge
  belongs_to :person

  validates :person, uniqueness: { scope: :badge, message: "already has this badge" }
  validate :team_membership

  # Removes the team badges among assignments whose holders are no longer
  # in the badge's team (the rule team_membership checks on save), so the
  # badge stops granting anything. Membership, team and badge changes call
  # this for the assignments they may affect. A badge whose team was deleted
  # has no members left, so its assignments go too.
  def self.remove_outside_team(assignments = all)
    assignments.joins(:badge).where.not(badges: { team_id: nil }).includes(:badge, :person).group_by(&:person).flat_map do |person, held|
      team_ids = person.all_teams.where(id: held.map { |assignment| assignment.badge.team_id }).ids
      held.reject { |assignment| team_ids.include?(assignment.badge.team_id) }.each(&:destroy!)
    end
  end

  def identifier_name
    "#{person.display_name} => #{badge.name}"
  end

  private

  def team_membership
    return true unless badge.present? && badge.team.present?
    errors.add(:person, " must be a member of the badge's team") unless person.all_teams.include?(badge.team)
  end
end
