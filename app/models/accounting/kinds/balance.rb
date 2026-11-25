# "Balance remaining": what's still owed on the person's matching charges,
# against the milestones (or, with none, each charge's own due date).
#
#   charged           = the charges' totals
#   balance remaining = the charges' balances (every payment, credit or
#                       discount applied to a charge lowers its balance)
#   paid              = charged - balance remaining
#
# Values, checked in order: not_invoiced (no charges), paid (nothing
# left), overdue (a milestone past its date and grace days isn't met),
# partial (something paid), unpaid.
class Accounting::Kinds::Balance < Accounting::Kinds::Base
  def evaluate
    charges = filter.apply(person_records.where(role: "charge")).order(Arel.sql("due_on NULLS LAST"), :txn_date, :external_id).to_a
    unapplied = person_records.where(role: %w[ payment credit ]).sum(:unapplied_cents)
    return outcome("not_invoiced", 0, empty_details(unapplied)) if charges.empty?

    charged = charges.sum { |charge| charge.total_cents.to_i }
    balance = charges.sum { |charge| charge.balance_cents.to_i }
    balance -= [ unapplied, balance ].min if rule.count_unapplied_credit?
    paid = [ charged - balance, 0 ].max

    checks = milestone_checks(charges, charged, balance)
    missed = checks.find { |check| !check[:met] && passed?(check[:due_on]) }
    coming = checks.find { |check| !check[:met] && !passed?(check[:due_on]) }

    value = if balance.zero? then "paid"
    elsif missed then "overdue"
    elsif paid.positive? then "partial"
    else "unpaid"
    end

    outcome(value, balance, {
      charged_cents: charged, paid_cents: paid, balance_cents: balance, unapplied_credit_cents: unapplied,
      on_plan: rule.on_plan?(person),
      charges: charges.map { |charge| charge_details(charge) },
      milestones: checks,
      missed: missed&.slice(:name, :due_on, :catch_up_cents),
      next: coming&.slice(:name, :due_on, :catch_up_cents)
    })
  end

  private
    # The rule's milestones (or the person's plan), each met or not, with
    # what it would take to meet it. With none, each charge with a due date
    # is due in full on that date; unapplied credit the rule counts covers
    # the earliest due first.
    def milestone_checks(charges, charged, balance)
      milestones = rule.milestones_for(person)
      checks = if milestones.any?
        milestones.map do |milestone|
          limit = milestone.limit_cents(charged)
          { key: milestone.id, name: milestone.name, due_on: milestone.due_on, limit_cents: limit, met: balance <= limit }
        end
      else
        credit = charges.sum { |charge| charge.balance_cents.to_i } - balance
        charges.select(&:due_on).map do |charge|
          covered = [ credit, charge.balance_cents.to_i ].min
          credit -= covered
          owed = charge.balance_cents.to_i - covered
          { key: "charge:#{charge.external_id}", name: "#{charge.public_label.presence || "Charge"} in full", due_on: charge.due_on,
            limit_cents: 0, met: owed.zero?, owed_cents: owed }
        end
      end
      checks.sort_by { |check| check[:due_on] }.map do |check|
        catch_up = check[:met] ? 0 : (check.delete(:owed_cents) || balance - check[:limit_cents])
        check.except(:owed_cents).merge(catch_up_cents: catch_up)
      end
    end

    # A milestone is missed once its date and the rule's grace days have
    # passed.
    def passed?(due_on)
      due_on + rule.grace_period < today
    end

    def charge_details(charge)
      { external_id: charge.external_id, label: charge.public_label, txn_date: charge.txn_date, due_on: charge.due_on,
        total_cents: charge.total_cents.to_i, balance_cents: charge.balance_cents.to_i, pay_url: charge.pay_url.presence }
    end

    def empty_details(unapplied)
      { charged_cents: 0, paid_cents: 0, balance_cents: 0, unapplied_credit_cents: unapplied, on_plan: rule.on_plan?(person),
        charges: [], milestones: [], missed: nil, next: nil }
    end
end
