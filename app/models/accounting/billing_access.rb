# Who may bill whom, and with what. Admins bill anyone with any active item,
# from a rule or from Account Status. Holders of a rule's badge grant with
# bill on bill from that rule only: the rule's people the badge covers,
# with the items the rule's filter names (none when it names no items).
class Accounting::BillingAccess
  attr_reader :viewer, :rule

  # viewer: a Person. rule: the rule billing starts from, if any.
  def initialize(viewer, rule = nil)
    @viewer = viewer
    @rule = rule
  end

  def admin?
    viewer&.admin? == true
  end

  # Whether the viewer may bill at all here: admins always; others from a
  # rule whose grant they hold with bill on.
  def allowed?
    return false unless viewer
    return true if admin?

    rule.present? && bill_grants.any?
  end

  # The people the viewer may bill.
  def people
    return Person.none unless allowed?
    return Person.all if admin?

    AudienceLevels.combine(bill_grants.map(&:covered_people)).where(id: rule.people.select(:id))
  end

  def may_bill?(person)
    person.present? && people.where(id: person.id).exists?
  end

  # The source's active items the viewer may bill for, by name.
  def items(source)
    return AccountingRecord.none unless allowed?

    scope = source.accounting_records.current.where(role: "item", active: true).order(:name)
    admin? ? scope : scope.where(external_id: rule.filters.to_h.fetch("items", []))
  end

  private
    def bill_grants
      @bill_grants ||= rule ? rule.grants_held_by(viewer).select(&:bill?) : []
    end
end
