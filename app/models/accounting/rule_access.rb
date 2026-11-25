# What one viewer may see of one person's result for one rule. The rule's
# levels are relative to that person (AudienceLevels), as person field and
# form levels are; holders of a granted badge (AccountingRuleBadgeGrant)
# see results as a leader would, and amounts too with amounts. Admins see
# everything. Must agree with AccountingRule#readable_people_for and
# #amount_people_for.
class Accounting::RuleAccess < AudienceAccess
  attr_reader :rule

  def initialize(viewer, subject, rule)
    super(viewer, subject)
    @rule = rule
  end

  def admin?
    viewer&.admin? == true
  end

  def can_read?
    return false unless viewer && subject
    return true if admin?

    rule.enabled? && (level_component(rule.read_permission).present? || grant.present?)
  end

  # Amounts, charges and pay links.
  def can_see_amounts?
    return false unless can_read?
    return true if admin?

    (level_component(rule.amount_permission).present? && level_component(rule.read_permission).present?) || grant&.amounts? == true
  end

  private
    def grant
      return @grant if defined?(@grant)
      return @grant = nil unless GatherPack::Features.enabled?(:badges)

      @grant = rule.badge_grants.includes(:badge).find { |candidate| viewer_badge_ids.include?(candidate.badge_id) && candidate.covers?(subject_team_ids) }
    end
end
