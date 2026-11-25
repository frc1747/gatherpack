# The Bill people preview: one row per person to bill, with the customers
# they're linked to (the one with the latest charge chosen), and a warning
# when billing them may be a mistake. Rows with a warning start unticked:
# already billed (a current charge matching the rule's filters, or without
# a rule this item since the invoice date), or no customer (to be created,
# or skipped when it can't be).
class Accounting::BillingPreview
  # Who to bill: the rule's people who aren't invoiced, a team (and the
  # teams below it), or people picked one by one.
  WHO = %w[ not_invoiced team people ].freeze
  # How many people a search adds at once.
  SEARCH_LIMIT = 20

  Row = Data.define(:person, :customers, :customer_id, :warning, :included) do
    def customer_name(id)
      customers.find { |customer| customer.customer_external_id == id }&.name.presence || id
    end
  end

  attr_reader :run, :access, :who, :team, :person_ids

  # run: an unsaved AccountingBillingRun holding what to charge.
  def initialize(run, access:, who:, team: nil, person_ids: [])
    @run = run
    @access = access
    @who = who
    @team = team
    @person_ids = Array(person_ids).compact_blank
  end

  def source
    run.gateway
  end

  def rule
    run.rule
  end

  # The choices for Who on this run.
  def self.who_choices(rule)
    rule&.balance? ? WHO : WHO - %w[ not_invoiced ]
  end

  def people
    scope = case who
    when "not_invoiced"
      rule&.balance? ? Person.where(id: rule.results.where(value: "not_invoiced").select(:person_id)) : Person.none
    when "team"
      team ? team.descendant_people : Person.none
    when "people"
      Person.where(id: person_ids)
    else
      Person.none
    end
    Person.where(id: scope.select(:id)).where(id: access.people.select(:id)).order(:last_name, :first_name)
  end

  def rows
    @rows ||= people.to_a.map { |person| row_for(person) }
  end

  # The row for one person: their customers and what to warn about.
  def row_for(person)
    customers = customers_for(person)
    customer_id = default_customer(customers)
    warning = if customers.empty?
      customer_warning
    elsif (charge = billed_charge(person))
      "Already billed: #{charge.public_label.presence || charge.number.presence || 'a charge'}"
    end
    Row.new(person: person, customers: customers, customer_id: customer_id, warning: warning, included: warning.nil?)
  end

  # Whether the source makes a customer for people who have none, and if
  # not, why.
  def customer_problem
    return "No customer: will be skipped" unless run.create_customers && run.capabilities.include?(:create_customers)

    problem = source.customer_creation_problem(rule&.team)
    "No customer: will be skipped (#{problem})" if problem
  end

  private
    def customer_warning
      customer_problem || "No customer: will be created"
    end

    def links
      @links ||= Accounting::CustomerLinks.new(source)
    end

    # The person's linked customers, as records (or stand-ins for customers
    # the source hasn't copied yet).
    def customers_for(person)
      ids = links.links.where(person: person).order(:created_at).pluck(:customer_external_id).uniq
      return [] if ids.empty?

      found = source.accounting_records.current.where(role: "customer", customer_external_id: ids).index_by(&:customer_external_id)
      ids.map { |id| found[id] || AccountingRecord.new(gateway_id: source.id, role: "customer", customer_external_id: id, name: id) }
    end

    # The customer with the latest charge; the first linked without any.
    def default_customer(customers)
      return nil if customers.empty?

      ids = customers.map(&:customer_external_id)
      latest = source.accounting_records.current.where(role: "charge", customer_external_id: ids)
        .order(Arel.sql("txn_date DESC NULLS LAST"), created_at: :desc).pick(:customer_external_id)
      latest || ids.first
    end

    # A current charge that means the person is already billed.
    def billed_charge(person)
      if rule
        scope = rule_records.records_for(person).where(role: "charge")
        Accounting::RecordFilter.new(rule.filters).apply(scope).order(txn_date: :desc).first
      else
        scope = source.accounting_records.current.where(role: "charge", voided: false, customer_external_id: links.customer_ids_for(person))
          .where("accounting_records.item_ids && ARRAY[?]::varchar[]", [ run.item_external_id.to_s ])
        scope = scope.where(txn_date: run.txn_date..) if run.txn_date
        scope.order(txn_date: :desc).first
      end
    end

    def rule_records
      @rule_records ||= Accounting::RuleRecords.new(rule)
    end
end
