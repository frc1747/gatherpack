# What a viewer sees of a rule's results at a glance: how many people have
# each value among those the viewer may see, and the money summed over the
# people whose amounts the viewer may see.
class Accounting::RuleSummary
  attr_reader :rule, :viewer

  def initialize(rule, viewer)
    @rule = rule
    @viewer = viewer
  end

  # The results the viewer may see. A custom rule's errors are for admins
  # only.
  def results
    @results ||= begin
      found = rule.results.where(person_id: rule.readable_people_for(viewer).select(:id))
      viewer&.admin? ? found : found.where.not(value: AccountingRule::ERROR)
    end
  end

  # The results whose amounts the viewer may see.
  def amount_results
    @amount_results ||= rule.results.where(person_id: rule.amount_people_for(viewer).select(:id))
  end

  def people_count
    @people_count ||= results.count
  end

  def amount_people_count
    @amount_people_count ||= amount_results.count
  end

  # [value, label, count] for each value someone has, in the rule's order.
  def counts
    @counts ||= begin
      found = results.group(:value).count
      ordered = rule.values.select { |value| found.key?(value) } + (found.keys - rule.values).sort
      ordered.map { |value| [ value, rule.label_for(value), found[value] ] }
    end
  end

  def amounts?
    amount_people_count.positive?
  end

  # Balance rules: charged, paid and balance remaining, summed. Other
  # kinds: the amount.
  def totals
    @totals ||= if rule.balance?
      sums = amount_results.pick(*%w[ charged_cents paid_cents balance_cents ].map { |key| Arel.sql("COALESCE(SUM((details->>'#{key}')::bigint), 0)") })
      { charged: sums[0], paid: sums[1], balance: sums[2] }
    else
      { amount: amount_results.sum(:amount_cents) }
    end
  end

  # Unapplied credit across the rule's people: admins only.
  def unapplied_credit_cents
    rule.results.pick(Arel.sql("COALESCE(SUM((details->>'unapplied_credit_cents')::bigint), 0)")).to_i
  end
end
