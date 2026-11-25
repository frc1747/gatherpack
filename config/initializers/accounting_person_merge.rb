# Accounting's columns for the person merge registry. Guarded, so this branch
# runs without feature/person-merge. to_prepare runs after every initializer,
# so the registry is loaded by then whatever the file order.
Rails.application.config.to_prepare do
  next unless defined?(GatherPack::PersonMerge)

  merge = GatherPack::PersonMerge

  # A customer linked to both people stays linked once, to the kept person.
  merge.register :accounting_customer_links, :person_id, unique_by: %i[gateway_id customer_external_id],
    model: AccountingCustomerLink, label: "Accounting customer links"
  merge.register :accounting_customer_links, :created_by_id, label: "Accounting customer links made"
  merge.register :accounting_customer_dismissals, :person_id, unique_by: %i[gateway_id customer_external_id],
    model: AccountingCustomerDismissal, label: "Accounting customers marked not theirs"
  # One answer per rule: the kept person's stands; the next evaluation
  # recomputes it from the merged links.
  merge.register :accounting_rule_results, :person_id, unique_by: :rule_id, model: AccountingRuleResult,
    label: "Accounting rule results"
  merge.register :accounting_uploads, :created_by_id, label: "Accounting files uploaded"
  merge.register :accounting_uploads, :applied_by_id, label: "Accounting files applied"
  # A payment plan moves to the kept person with its rows.
  merge.register :accounting_person_milestones, :person_id, label: "Accounting payment plans"
  merge.register :accounting_person_milestones, :created_by_id, label: "Accounting payment plans made"
  merge.register :accounting_reminders, :person_id, label: "Accounting reminders about them"
  merge.register :accounting_reminders, :recipient_id, label: "Accounting reminders sent to them"
  # One line per person in a run: the kept person's stands.
  merge.register :accounting_billing_lines, :person_id, unique_by: :run_id, model: AccountingBillingLine,
    label: "Accounting billing lines"
  merge.register :accounting_billing_runs, :created_by_id, label: "Accounting billing runs started"
end
