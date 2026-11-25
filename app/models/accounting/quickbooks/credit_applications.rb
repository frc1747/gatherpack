# QuickBooks records where a credit memo was used on the payment that
# applies it, not on the credit memo. After a sync, this fills each credit
# memo's applied_to from the payments of the same customers, so normalize
# can stay one record at a time.
class Accounting::Quickbooks::CreditApplications
  def initialize(gateway)
    @gateway = gateway
  end

  # records: the records a sync just saved.
  def resolve(records)
    customers = records.select { |record| %w[ payment credit ].include?(record.role) }.filter_map(&:customer_external_id).uniq
    return if customers.empty?

    scope = @gateway.accounting_records.current.where(customer_external_id: customers)
    applied = Hash.new { |hash, key| hash[key] = Hash.new(0) }

    scope.where(entity_type: "Payment").find_each do |payment|
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

    scope.where(entity_type: "CreditMemo").find_each do |credit|
      applied_to = applied[credit.external_id].map { |id, amount| { "external_id" => id, "amount_cents" => amount } }
      # Not a change in QuickBooks, so no hooks.
      credit.update_columns(applied_to: applied_to) unless credit.applied_to == applied_to
    end
  end
end
