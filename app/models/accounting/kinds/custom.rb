# "Custom": an architect's Ruby, run the way hooks run, with
#   person    the person being evaluated
#   rule      the rule
#   records   the person's matching AccountingRecord scope (filters applied;
#             custom code may read the raw source data)
#   customers the person's linked customer records
# It returns { value:, amount_cents:, details: } or a string (the value).
# An exception gives the value "error", shown to admins only. The code runs
# through Hook#run, the one place stored Ruby is evaluated; the four names
# are set on the code's first line, so line numbers in errors still match.
class Accounting::Kinds::Custom < Accounting::Kinds::Base
  Context = Struct.new(:person, :rule, :records, :customers)

  def evaluate
    context = Context.new(person, rule, filter.apply(person_records), records.customers_for(person))
    code = "person, rule, records, customers = model.to_a; #{rule.code}"
    returned = Hook.new(name: "accounting rule #{rule.key}", code: code).run(context)
    case returned
    when Hash
      returned = returned.with_indifferent_access
      outcome(returned[:value].to_s.presence || AccountingRule::ERROR, returned[:amount_cents]&.to_i, (returned[:details] || {}).to_h)
    else
      outcome(returned.to_s.presence || AccountingRule::ERROR, nil, {})
    end
  rescue StandardError, ScriptError => e
    outcome(AccountingRule::ERROR, nil, { error: "#{e.class}: #{e.message}".truncate(500) })
  end
end
