# Who a checklist covers (item_id nil), or who one item applies to (item_id
# set): include or exclude a team (and every team below it, with or without
# managers), a badge's holders, one person, or the applicants to a team
# (pending membership applications to it or a team below it). See
# Checklists::Population.
class ChecklistRule < ApplicationRecord
  has_neat_id :chlr
  include CanBeHooked
  has_paper_trail versions: { class_name: "AuditLog" }

  belongs_to :checklist, inverse_of: :checklist_rules
  belongs_to :item, class_name: "ChecklistItem", optional: true, inverse_of: :checklist_rules
  belongs_to :team, optional: true
  belongs_to :badge, optional: true
  belongs_to :person, optional: true

  enum :effect, { include: 0, exclude: 1 }, prefix: :effect, validate: true
  enum :target_type, { team: 0, badge: 1, person: 2, applicants: 3 }, prefix: :target, validate: true

  validate :target_present
  validate :within_checklist_team
  validate :item_on_checklist
  validates :checklist_id, uniqueness: { scope: %i[item_id effect target_type team_id badge_id person_id], message: "already has this rule" }

  before_validation :clear_other_targets
  after_commit :refresh_checklist

  def identifier_name
    "#{checklist&.title}: #{description}"
  end

  def target
    case target_type
    when "team", "applicants" then team
    when "badge" then badge
    when "person" then person
    end
  end

  # "Include Den A (members only)"
  def description
    text = "#{effect.capitalize} "
    text += "applicants to " if target_applicants?
    text += target&.identifier_name || "(deleted)"
    text += " badge holders" if target_badge?
    text += " (members only, not managers)" if target_team? && !include_managers?
    text
  end

  private

  def target_present
    errors.add(:base, "Choose who the rule is about") if target.nil?
  end

  # Everyone covered is within the checklist's team and below; applicants
  # are within the team they applied to, which must be too.
  def within_checklist_team
    return if checklist.nil? || target.nil? || item_id.present?

    reach = Checklists.team_subtree_ids(checklist.team_id)
    inside = case target_type
    when "team", "applicants" then reach.include?(team_id)
    when "badge" then badge.team_id.nil? || reach.include?(badge.team_id)
    when "person" then Membership.where(person_id: person_id, team_id: reach).exists? ||
      MembershipApplication.pending.where(person_id: person_id, team_id: reach).exists?
    end
    errors.add(:base, "Must be within #{checklist.team.name} or a team below it") unless inside
  end

  def item_on_checklist
    errors.add(:item, "must be on this checklist") if item && item.checklist_id != checklist_id
  end

  def clear_other_targets
    self.team_id = nil unless target_team? || target_applicants?
    self.badge_id = nil unless target_badge?
    self.person_id = nil unless target_person?
    self.include_managers = true unless target_team?
  end

  def refresh_checklist
    return unless Checklists.enabled?

    found = Checklist.find_by(id: checklist_id)
    Checklists.mark(found, :all) if found && !found.archived?
  end
end
