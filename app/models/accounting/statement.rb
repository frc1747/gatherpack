# A person's statement: one table of the records the viewer may see, with
# a running balance. Everyone but admins sees the charges matched by rules
# whose amounts they may see, the payments, credits and refunds applied to
# those charges (by the amount applied to them), and the linked customers'
# money not applied to any charge, each by its public label only. Admins
# see every record of the person's linked customers, with descriptions.
class Accounting::Statement
  # What a row shows. charge_cents raises what's owed, payment_cents lowers
  # it; balance_cents is the running balance after the row.
  Row = Struct.new(:record, :date, :label, :charge_cents, :payment_cents, :balance_cents, :description, :external_url, keyword_init: true)

  # Charges count up; payments and credits count down; a refund pays money
  # back, so it counts up; a receipt was charged and paid at once.
  CHARGE_ROLES = %w[ charge refund receipt ].freeze
  PAYMENT_ROLES = %w[ payment credit receipt ].freeze
  APPLIED_ROLES = %w[ payment credit refund ].freeze

  attr_reader :viewer, :person

  def initialize(viewer, person)
    @viewer = viewer
    @person = person
  end

  def admin?
    viewer&.admin? == true
  end

  # The rules whose amounts the viewer may see for this person.
  def rules
    @rules ||= Accounting::Access.visible_results(viewer&.user, person).map(&:rule)
      .select { |rule| Accounting::RuleAccess.new(viewer, person, rule).can_see_amounts? }
  end

  def visible?
    admin? || rules.any?
  end

  # Newest first.
  def rows
    @rows ||= begin
      running = 0
      oldest_first.map do |row|
        running += row.charge_cents.to_i - row.payment_cents.to_i
        row.balance_cents = running
        row
      end.reverse
    end
  end

  def balance_cents
    rows.first&.balance_cents.to_i
  end

  private
    def oldest_first
      found = admin? ? admin_rows : member_rows
      found.sort_by { |row| [ row.date || Date.new(1900), row.charge_cents.to_i.positive? ? 0 : 1, row.record.external_id ] }
    end

    # Every record of the person's linked customers, on every source.
    def admin_rows
      sources.flat_map do |source|
        records_for(source).where.not(role: %w[ customer item category other ]).map do |record|
          Row.new(record: record, date: record.txn_date, label: record.identifier_name, description: record.description,
            charge_cents: (record.total_cents.to_i if CHARGE_ROLES.include?(record.role)),
            payment_cents: (record.total_cents.to_i if PAYMENT_ROLES.include?(record.role)),
            external_url: (record.external_url if source.capabilities.include?(:deep_links)))
        end
      end
    end

    def member_rows
      rules.group_by(&:gateway).flat_map do |source, source_rules|
        records = records_for(source)
        charges = source_rules.flat_map { |rule| rule_charges(rule, records) }.uniq(&:id)
        charge_ids = charges.map(&:external_id).to_set

        charge_rows = charges.map { |charge| member_row(charge, charge_cents: charge.total_cents.to_i) }
        applied_rows = records.where(role: APPLIED_ROLES).filter_map do |record|
          applied = Array(record.applied_to).sum { |entry| charge_ids.include?(entry["external_id"].to_s) ? entry["amount_cents"].to_i : 0 }
          unapplied = record.role == "refund" ? 0 : record.unapplied_cents.to_i
          next if applied.zero? && unapplied.zero?

          record.role == "refund" ? member_row(record, charge_cents: applied) : member_row(record, payment_cents: applied + unapplied)
        end
        charge_rows + applied_rows
      end
    end

    # The charges a rule reads (AccountingRule#reads_charges?), by its filters.
    def rule_charges(rule, records)
      return [] unless rule.reads_charges?

      Accounting::RecordFilter.new(rule.filters).apply(records.where(role: "charge")).to_a
    end

    # Only the public label: never a memo, note or credit reason.
    def member_row(record, charge_cents: nil, payment_cents: nil)
      Row.new(record: record, date: record.txn_date, label: record.public_label.presence || record.role.humanize,
        charge_cents: charge_cents, payment_cents: payment_cents)
    end

    def sources
      gateway_ids = AccountingCustomerLink.where(person: person).distinct.pluck(:gateway_id)
      Gateway.where(id: gateway_ids).select { |gateway| gateway.is_a?(Accounting::Provider) }
    end

    def records_for(source)
      ids = Accounting::CustomerLinks.new(source).customer_ids_for(person)
      source.accounting_records.current.where(voided: false, customer_external_id: ids)
    end
end
