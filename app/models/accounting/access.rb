# Who sees the accounting screens at all: the Account Status list when the
# viewer may see some rule's results, and a person's Account tab when the
# viewer may see at least one of that person's results.
module Accounting::Access
  # Rules whose results the viewer may see for anyone: every rule for
  # admins, enabled ones reaching someone for everyone else.
  def self.visible_rules(user)
    person = user&.person
    return AccountingRule.none unless person
    return AccountingRule.ordered if person.admin?

    AccountingRule.enabled.ordered.includes(:team, :badge_grants).select do |rule|
      rule.readable_people_for(person).where(id: rule.results.where.not(value: AccountingRule::ERROR).select(:person_id)).exists?
    end
  end

  def self.sees_any_rule?(user)
    person = user&.person
    return false unless person
    return true if person.admin?

    visible_rules(user).any?
  end

  # The rules with a result for the person that the viewer may see.
  def self.visible_results(user, person)
    viewer = user&.person
    return AccountingRuleResult.none unless viewer && person

    results = AccountingRuleResult.where(person: person).joins(:rule).includes(rule: :gateway)
      .merge(AccountingRule.ordered)
    results = results.merge(AccountingRule.enabled) unless viewer.admin?
    results = results.where.not(value: AccountingRule::ERROR) unless viewer.admin?
    results.select { |result| Accounting::RuleAccess.new(viewer, person, result.rule).can_read? }
  end

  def self.sees_any_result?(user, person)
    visible_results(user, person).any?
  end
end
