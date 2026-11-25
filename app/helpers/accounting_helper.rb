module AccountingHelper
  ROLE_NAMES = {
    "customer" => "Customer", "charge" => "Charge", "receipt" => "Receipt", "payment" => "Payment", "credit" => "Credit",
    "refund" => "Refund", "item" => "Item", "category" => "Category", "other" => "Other"
  }.freeze

  LINK_SOURCE_NAMES = {
    "confirmed" => "Suggested, confirmed", "manual" => "Picked by an admin", "reference" => "Reference match",
    "ledger_owner" => "Ledger owner", "created" => "Created by billing"
  }.freeze

  def accounting_link_source_name(source)
    LINK_SOURCE_NAMES.fetch(source.to_s, source.to_s.humanize)
  end

  def accounting_role_name(role)
    ROLE_NAMES.fetch(role.to_s, role.to_s.humanize)
  end

  def accounting_cents(cents)
    cents.nil? ? "" : Money.new(cents).format
  end

  VALUE_COLORS = {
    "paid" => "success", "partial" => "warning", "overdue" => "danger", "unpaid" => "secondary", "not_invoiced" => "secondary",
    "some" => "primary", "none" => "secondary", "error" => "dark"
  }.freeze

  ACCESS_LEVEL_NAMES = {
    "admin" => "Admins only", "self" => "The person", "leaders" => "Their leaders", "self_and_leaders" => "The person and their leaders",
    "guardians" => "Their guardians and leaders", "family" => "The person, their guardians and leaders",
    "team" => "The person, guardians, leaders and teammates", "everyone" => "Everyone signed in"
  }.freeze

  def accounting_level_choices
    ACCESS_LEVEL_NAMES.map { |level, name| [ name, level ] }
  end

  # A result's value as a colored badge, in the rule's words.
  def accounting_value_badge(rule, value)
    return "" if value.blank?

    tag.span rule.label_for(value), class: "badge text-bg-#{VALUE_COLORS.fetch(value.to_s, "info")}"
  end

  # The milestone line under a balance result: the missed milestone, or the
  # next one. Amounts only for viewers who may see them; dates too.
  def accounting_milestone_line(result, amounts:)
    missed = result.detail(:missed)
    coming = result.detail(:next)
    if result.value == "overdue" && missed
      [ "Overdue: #{missed["name"]}", (accounting_catch_up(missed) if amounts) ].compact.join(" · ")
    elsif coming && result.value != "paid"
      amounts ? "Next: #{accounting_cents(coming["catch_up_cents"])} by #{accounting_date(coming["due_on"])}" : "Next: #{coming["name"]}"
    end
  end

  def accounting_catch_up(milestone)
    "#{accounting_cents(milestone["catch_up_cents"])} to meet #{milestone["name"]}"
  end

  # The amount column: a balance's remaining amount, a count's number.
  def accounting_result_amount(result)
    result.rule.kind == "count" ? result.detail(:count).to_i.to_s : accounting_cents(result.amount_cents)
  end

  def accounting_date(value)
    date = value.is_a?(String) ? Date.iso8601(value) : value
    date ? l(date, format: :short) : ""
  rescue Date::Error
    value.to_s
  end

  # The rule page's CSV. Charges are named by their public label only, and
  # amounts are left blank for people whose amounts the viewer may not see.
  def accounting_rule_csv(rule, results, amount_ids)
    require "csv"
    CSV.generate do |csv|
      csv << [ "Last name", "First name", "Team", "Status", "Amount", "Charges", "Changed on" ]
      results.each do |result|
        person = result.person
        amounts = amount_ids.include?(person.id)
        csv << [ person.last_name, person.first_name, person.teams.map(&:name).sort.join("; "), rule.label_for(result.value),
          (accounting_result_amount(result) if amounts), (result.charges.map { |charge| charge["label"] }.compact.join("; ") if amounts),
          result.changed_at&.to_date&.iso8601 ].map { |cell| accounting_csv_cell(cell) }
      end
    end
  end

  # Spreadsheets run a cell that starts with =, +, -, @, a tab or a carriage
  # return as a formula, so such cells are written as text.
  def accounting_csv_cell(value)
    text = value.to_s
    text.match?(/\A[=+\-@\t\r]/) ? "'#{text}" : value
  end
end
