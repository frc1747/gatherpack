# One rule in a form's audience: include or exclude a team (and every team
# below it), a badge's holders, or one person. The audience is computed from
# the rules whenever it's needed (Form#audience), so people who join a team
# later are asked automatically.
class FormAudienceRule < ApplicationRecord
  has_neat_id :frmar
  include CanBeHooked
  has_paper_trail versions: { class_name: "AuditLog" }

  belongs_to :form
  belongs_to :team, optional: true
  belongs_to :badge, optional: true
  belongs_to :person, optional: true

  enum :effect, { include: 0, exclude: 1 }, prefix: :effect, validate: true
  enum :target_type, { team: 0, badge: 1, person: 2 }, prefix: :target, validate: true

  validate :target_matches_type
  validate :within_completion_badge_team
  validates :form_id, uniqueness: { scope: %i[ effect target_type team_id badge_id person_id ], message: "already has this rule" }

  before_validation :clear_other_targets

  scope :includes_first, -> { order(:effect, :target_type, :created_at) }

  def identifier_name
    "#{form&.title}: #{description}"
  end

  def target
    case target_type
    when "team" then team
    when "badge" then badge
    when "person" then person
    end
  end

  # "Include Den A (members only)"
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

  # Whether everyone this rule covers is in the team or a team below it.
  def within_team?(outer)
    return true if outer.nil?

    outer_ids = outer.all_descendant_ids + [ outer.id ]
    case target_type
    when "team" then outer_ids.include?(team_id)
    when "badge" then badge&.team_id.present? && outer_ids.include?(badge.team_id)
    when "person" then Membership.where(person_id: person_id, team_id: outer_ids).exists?
    end
  end

  private

  def team_people
    team_ids = team.all_descendant_ids + [ team.id ]
    memberships = Membership.where(team_id: team_ids)
    memberships = memberships.where(manager: false) unless include_managers?
    Person.where(id: memberships.select(:person_id))
  end

  def clear_other_targets
    self.team_id = nil unless target_team?
    self.badge_id = nil unless target_badge?
    self.person_id = nil unless target_person?
    self.include_managers = true unless target_team?
  end

  # See Form#completion_badge_reaches_audience.
  def within_completion_badge_team
    badge_team = form&.completion_badge&.team
    return unless effect_include? && badge_team && target && !within_team?(badge_team)

    errors.add(:base, "Everyone asked must be in #{badge_team.name}, because the completion badge belongs to it")
  end

  def target_matches_type
    errors.add(target_type.to_sym, "can't be blank") if target_type && target.nil?
  end
end
