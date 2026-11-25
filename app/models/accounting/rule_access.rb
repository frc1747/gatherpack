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

    rule.enabled? && (level_component(rule.read_permission).present? || granted?)
  end

  # Amounts, charges and pay links.
  def can_see_amounts?
    return false unless can_read?
    return true if admin?

    (level_component(rule.amount_permission).present? && level_component(rule.read_permission).present?) || granted?(amounts: true)
  end

  # A payment plan's milestones (names, dates and amounts): the person,
  # their guardians and admins, among those who see the result. Leaders and
  # badge-grant holders see only the status, since a plan can reveal
  # hardship. Amounts still follow #can_see_amounts?.
  def sees_plan?
    return false unless can_read?

    admin? || component?(:subject) || component?(:guardian)
  end

  # Whether the viewer may see the result's milestone line: everyone who
  # sees the result, unless the person is on a plan the viewer may not see.
  def plan_hidden?(result)
    result.on_plan? && !sees_plan?
  end

  private
    # Whether any grant the viewer holds covers the subject (and shows
    # amounts, with amounts).
    def granted?(amounts: false)
      @held_grants ||= rule.grants_held_by(viewer)
      @held_grants.any? { |grant| (!amounts || grant.amounts?) && grant.covers?(subject_team_ids) }
    end
end
