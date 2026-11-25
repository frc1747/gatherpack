# The model of the "accounting_rules - result changed" hook: one person's
# result for one rule changed value or amount. new_value is nil when the
# person no longer has a result (they stopped qualifying).
AccountingRuleChange = Struct.new(:rule, :person, :old_value, :new_value, :old_amount_cents, :new_amount_cents,
  :unapplied_credit_cents, :on_plan, keyword_init: true) do
  def identifier_name
    "#{rule.name}: #{person.identifier_name} #{rule.label_for(old_value).presence || "none"} → #{rule.label_for(new_value).presence || "none"}"
  end
end
