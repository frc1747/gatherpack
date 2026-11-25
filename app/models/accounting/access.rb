# Who sees the accounting screens at all: the Account Status list when the
# viewer may see some rule's results, and a person's Account tab when the
# viewer may see at least one of that person's results or may copy their id
# into a customer's reference.
module Accounting::Access
  MATCHING_BADGE_SETTING = :accounting_customer_matching_badge

  # The badge (setting accounting_customer_matching_badge, by name) whose
  # holders may match customers to people, like admins. Only an
  # admin-assigned badge counts, and only while Badges are on.
  def self.matching_badge
    name = Settings[MATCHING_BADGE_SETTING].to_s.strip
    return nil if name.blank? || !GatherPack::Features.enabled?(:badges)

    Badge.added_by_admin.find_by("LOWER(name) = ?", name.downcase)
  end

  # Whether the user may match customers to people: an admin, or a holder
  # of the matching badge.
  def self.customer_matcher?(user)
    return true if user&.admin == true

    person = user&.person
    badge = matching_badge
    badge.present? && person.present? && BadgeAssignment.exists?(badge: badge, person: person)
  end

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

  # The sources that match customers to people by a reference the customer
  # carries, when the viewer may match customers: the Account tab shows
  # them the person's GatherPack ID to copy there.
  def self.reference_sources(user)
    return [] unless customer_matcher?(user)

    Accounting.sources.select { |source| source.match_strategy_list.include?("reference") }
  end

  # Whether the Account tab shows: the viewer may see one of the person's
  # results, or may copy the person's id into a source's reference.
  def self.sees_account_tab?(user, person)
    sees_any_result?(user, person) || reference_sources(user).any?
  end
end
