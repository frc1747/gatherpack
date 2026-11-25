# "Amount": a sum of the person's matching records. measure:
#   invoiced: charge and receipt totals; with items, only matching lines.
#   paid:     payment and receipt totals minus refund totals; with items,
#             what payments applied to matching charges, plus receipts'
#             matching lines, minus refunds' matching lines.
# Values: some (more than zero), none.
class Accounting::Kinds::Amount < Accounting::Kinds::Base
  def evaluate
    cents = rule.measure == "paid" ? paid : invoiced
    outcome(cents.positive? ? "some" : "none", cents, { measure: rule.measure })
  end

  private
    def invoiced
      sum(filter.apply(with_roles(%w[ charge receipt ])))
    end

    def paid
      incoming = filter.items.any? ? applied_to_matching_charges + sum(filter.apply(with_roles(%w[ receipt ]))) : sum(filter.apply(with_roles(%w[ payment receipt ])))
      incoming - sum(filter.apply(with_roles(%w[ refund ])))
    end

    def applied_to_matching_charges
      charge_ids = filter.apply(person_records.where(role: "charge")).pluck(:external_id).to_set
      filter.apply(with_roles(%w[ payment ]), items: false).pluck(:applied_to).sum do |applied|
        Array(applied).sum { |entry| charge_ids.include?(entry["external_id"].to_s) ? entry["amount_cents"].to_i : 0 }
      end
    end

    def sum(scope)
      return scope.sum(:total_cents) if filter.items.empty?

      scope.to_a.sum { |record| filter.line_cents(record) }
    end
end
