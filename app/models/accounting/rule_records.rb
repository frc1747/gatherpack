# The records a rule reads for a person: every current, non-voided record
# of the rule's source whose customer is linked to them (with the parent
# rollup, sub-customers too). Build one per rule evaluation, so the links
# and customer tree load once.
class Accounting::RuleRecords
  attr_reader :rule

  def initialize(rule)
    @rule = rule
    @links = Accounting::CustomerLinks.new(rule.gateway)
  end

  def filter
    @filter ||= Accounting::RecordFilter.new(rule.filters)
  end

  def customer_ids_for(person)
    @links.customer_ids_for(person)
  end

  # Everything but the customer rows themselves.
  def records_for(person)
    source_records.where(voided: false, customer_external_id: customer_ids_for(person)).where.not(role: "customer")
  end

  # The customer rows linked to the person.
  def customers_for(person)
    source_records.where(role: "customer", customer_external_id: customer_ids_for(person))
  end

  private
    def source_records
      rule.gateway.accounting_records.current
    end
end
