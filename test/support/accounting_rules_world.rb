require_relative "accounting_world"

# Helpers for accounting rule tests: a source with records in the neutral
# columns (as any source's normalize leaves them), people linked to its
# customers, teams, badges and rules. Northwind people throughout.
module AccountingRulesWorld
  include AccountingWorld

  def accounting_source
    @accounting_source ||= create_quickbooks_gateway(connected: false)
  end

  # A person with a login, linked to their own customer when customer: is
  # given.
  def create_rule_person(first_name, last_name, team: nil, manager: false, admin: false, customer: nil, source: accounting_source)
    user = User.create!(email: "#{first_name}.#{last_name}@example.com".downcase, password: "Password1!", admin: admin)
    person = Person.create!(user: user, first_name: first_name, last_name: last_name)
    Membership.create!(person: person, team: team, manager: manager) if team
    link_customer(person, customer, source: source) if customer
    person
  end

  def link_customer(person, customer_id, source: accounting_source)
    unless source.accounting_records.exists?(role: "customer", customer_external_id: customer_id)
      create_customer_record(source, customer_id, name: "#{person.last_name}, #{person.first_name}")
    end
    Accounting::CustomerLinks.new(source).link!(customer_id, person, source: "manual")
  end

  def create_rule_team(name, parent: nil)
    Team.create!(name: name, team_type: team_types(:one), parent: parent)
  end

  def create_rule_badge(name, team: nil, permission: :added_by_admin)
    Badge.create!(name: name, short: name.first(3), color: "#336699", badge_type: badge_types(:one), team: team, permission: permission)
  end

  def create_rule(name = "2027 Membership Dues", kind: "balance", source: accounting_source, milestones: [], **attributes)
    rule = AccountingRule.create!(name: name, kind: kind, gateway: source, **attributes)
    milestones.each { |milestone| rule.milestones.create!(milestone) }
    rule
  end

  # Records in the neutral columns. Money in cents.
  def add_record(customer_id, role, external_id, source: accounting_source, **columns)
    source.accounting_records.create!({ entity_type: role.to_s.camelize, external_id: external_id, role: role.to_s,
      customer_external_id: customer_id, data: {} }.merge(columns))
  end

  def add_charge(customer_id, external_id, total:, balance: total, due_on: nil, txn_date: Date.new(2026, 9, 1), items: [], label: nil, **columns)
    add_record(customer_id, "charge", external_id, total_cents: total, balance_cents: balance, due_on: due_on, txn_date: txn_date,
      item_ids: items, lines: items.map { |item| { "item_id" => item, "amount_cents" => total / items.size } },
      public_label: label || "Invoice #{external_id}", **columns)
  end

  def add_payment(customer_id, external_id, total:, applied: {}, unapplied: 0, role: "payment", txn_date: Date.new(2026, 9, 15), **columns)
    add_record(customer_id, role, external_id, total_cents: total, unapplied_cents: unapplied, txn_date: txn_date,
      applied_to: applied.map { |charge_id, cents| { "external_id" => charge_id, "amount_cents" => cents } },
      public_label: role.to_s.humanize, **columns)
  end

  def evaluate(rule, today: Date.current)
    Accounting::Evaluation.new(rule, today: today).run
  end

  def result_for(rule, person)
    rule.results.find_by(person: person)
  end

  def outcome_for(rule, person, today: Date.current)
    Accounting::Evaluation.new(rule, today: today).outcome_for(person)
  end
end
