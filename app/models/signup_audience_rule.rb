# One rule in a sheet's audience: include or exclude a team (and every team
# below it), a badge's holders, or one person. See SignupSheet#audience.
class SignupAudienceRule < ApplicationRecord
  has_neat_id :suar
  include CanBeHooked
  has_paper_trail versions: { class_name: "AuditLog" }

  belongs_to :signup_sheet
  belongs_to :team, optional: true
  belongs_to :badge, optional: true
  belongs_to :person, optional: true

  enum :effect, { include: 0, exclude: 1 }, prefix: :effect, validate: true
  enum :target_type, { team: 0, badge: 1, person: 2 }, prefix: :target, validate: true

  validate :target_matches_type
  validates :signup_sheet_id, uniqueness: { scope: %i[ effect target_type team_id badge_id person_id ], message: "already has this rule" }

  before_validation :clear_other_targets

  scope :includes_first, -> { order(:effect, :target_type, :created_at) }

  def identifier_name
    "#{signup_sheet&.title}: #{description}"
  end

  def target
    case target_type
    when "team" then team
    when "badge" then badge
    when "person" then person
    end
  end

  # "Include Den A (members only, not managers)"
  def description
    text = "#{effect.capitalize} #{target&.identifier_name || "(deleted)"}"
    text += " badge holders" if target_badge?
    text += " (members only, not managers)" if target_team? && !include_managers?
    text
  end

  # The people this rule covers, as a relation.
  def people
    case target_type
    when "team" then team_people
    when "badge" then Person.where(id: BadgeAssignment.where(badge_id: badge_id).select(:person_id))
    when "person" then Person.where(id: person_id)
    end
  end

  private

  def team_people
    memberships = Membership.where(team_id: team.all_descendant_ids + [ team.id ])
    memberships = memberships.where(manager: false) unless include_managers?
    Person.where(id: memberships.select(:person_id))
  end

  def clear_other_targets
    self.team_id = nil unless target_team?
    self.badge_id = nil unless target_badge?
    self.person_id = nil unless target_person?
    self.include_managers = true unless target_team?
  end

  def target_matches_type
    errors.add(target_type.to_sym, "can't be blank") if target_type && target.nil?
  end
end
