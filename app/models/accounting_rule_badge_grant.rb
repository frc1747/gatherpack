# Lets holders of a badge see a rule's results for the people the badge
# covers, as a leader would, for a treasurer or mentors who aren't team
# managers. amounts: they see amounts and pay links too. bill: they may
# bill the rule's people. As with form and person field grants, only badges
# admins assign can grant access, and a team badge covers only people in
# that team or below it. No hooks: a settings row, whose changes show in the
# audit log with its rule.
class AccountingRuleBadgeGrant < ApplicationRecord
  has_neat_id :arbg
  has_paper_trail versions: { class_name: "AuditLog" }

  belongs_to :rule, class_name: "AccountingRule", inverse_of: :badge_grants
  belongs_to :badge

  validates :badge_id, uniqueness: { scope: :rule_id }
  validate :badge_is_admin_assigned

  # Whether the grant counts at all: see BadgeAccessGrants.
  def effective?
    badge.grant_effective?
  end

  def covers?(subject_team_ids)
    effective? && (badge.team_id.nil? || subject_team_ids.include?(badge.team_id))
  end

  # Goes by team_id: a badge whose team was deleted covers nobody, not
  # everyone.
  def covered_people
    return Person.none unless effective?
    return Person.all if badge.team_id.nil?

    badge.team ? badge.team.descendant_people : Person.none
  end

  def identifier_name
    "#{badge&.name}: can see #{amounts? ? "results and amounts" : "results"} of #{rule&.name}"
  end

  private
    # Otherwise anyone who can assign the badge to themselves could grant
    # themselves access to people's accounts.
    def badge_is_admin_assigned
      errors.add(:badge, "must be one only admins can assign") if badge && !badge.added_by_admin?
    end
end
