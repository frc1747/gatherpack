module AccountingBillingHelper
  LINE_STATUS_COLORS = { "pending" => "secondary", "created" => "success", "failed" => "danger", "skipped" => "warning", "exported" => "primary" }.freeze

  # The source's word for a charge, lowercase: "invoice" in QuickBooks.
  def accounting_charge_word(source)
    (source.respond_to?(:role_label) ? source.role_label("charge") : "charge").to_s.downcase
  end

  # "Create 38 invoices in QuickBooks?"
  def accounting_billing_question(run, count)
    "Create #{pluralize(count, accounting_charge_word(run.gateway))} in #{run.gateway.source_name}?"
  end

  def accounting_billing_button(run)
    "Create #{accounting_charge_word(run.gateway).pluralize}"
  end

  def accounting_line_status_badge(line)
    tag.span(line.status_name, class: "badge text-bg-#{LINE_STATUS_COLORS.fetch(line.status, 'secondary')}")
  end

  # The run's state in words: "Finished Nov 24 · 38 created, 2 failed".
  def accounting_billing_run_state(run, details)
    counts = details.filter_map { |status, count| "#{count} #{AccountingBillingLine::STATUS_NAMES.fetch(status).downcase}" if count.positive? }
    state = if run.finished?
      [ "Finished", (l(run.finished_at.to_date, format: :short) if run.finished_at) ].compact.join(" ")
    else
      "Working through the lines"
    end
    [ state, *counts ].join(" · ")
  end

  def accounting_who_label(who, rule)
    case who
    when "not_invoiced" then "#{rule.name}: people who are #{rule.label_for('not_invoiced')}"
    when "team" then "A team, and the teams below it"
    when "people" then "People I pick"
    end
  end
end
