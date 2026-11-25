# QuickBooks records where a credit memo was used on the payment that
# applies it, not on the credit memo. This works out each credit memo's
# applied_to from the copied payments of the same customer, so normalize
# can stay one record at a time: before a credit memo is saved (so its
# hooks see the value), and after a sync for credit memos whose payments
# came in later.
class Accounting::Quickbooks::CreditApplications
  def initialize(gateway)
    @gateway = gateway
  end

  # The applied_to a credit memo record should have now.
  def applied_to_for(credit)
    return [] if credit.customer_external_id.blank?

    to_rows(allocations([ credit.customer_external_id ])[credit.external_id])
  end

  # records: the records a sync just saved.
  def resolve(records)
    customers = records.select { |record| %w[ payment credit ].include?(record.role) }.filter_map(&:customer_external_id).uniq
    return if customers.empty?

    applied = allocations(customers)
    current(customers).where(entity_type: "CreditMemo").find_each do |credit|
      applied_to = to_rows(applied[credit.external_id])
      # Not a change in QuickBooks, so no hooks.
      credit.update_columns(applied_to: applied_to) unless credit.applied_to == applied_to
    end
  end

  private
    def current(customers)
      @gateway.accounting_records.current.where(customer_external_id: customers)
    end

    # credit memo id => { invoice id => cents }, from the customers' payments.
    def allocations(customers)
      applied = Hash.new { |hash, key| hash[key] = Hash.new(0) }

      current(customers).where(entity_type: "Payment").find_each do |payment|
        _, left = Accounting::Quickbooks::Normalizer.allocate_payment(payment.data)
        Accounting::Quickbooks::Normalizer.linked(payment.data, "CreditMemo").each do |credit_id, amount|
          amount = amount.to_i
          left.each do |line|
            take = [ line[1], amount ].min
            next unless take.positive?

            applied[credit_id][line[0]] += take
            line[1] -= take
            amount -= take
          end
        end
      end
      applied
    end

    def to_rows(applied)
      Array(applied).map { |id, amount| { "external_id" => id, "amount_cents" => amount } }
    end
end
