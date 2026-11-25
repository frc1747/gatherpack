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
  # next one. Amounts only for viewers who may see them; dates too. With
  # status_only: (a rule with payment plans, for viewers who mayn't see
  # them; Accounting::RuleAccess#status_only?), only "On schedule" or
  # "Overdue": no names, dates or amounts.
  def accounting_milestone_line(result, amounts:, status_only: false)
    missed = result.detail(:missed)
    coming = result.detail(:next)
    if status_only
      { "partial" => "On schedule", "unpaid" => "On schedule", "overdue" => "Overdue" }[result.value]
    elsif result.value == "overdue" && missed
      [ "Overdue: #{missed["name"]}", (accounting_catch_up(missed) if amounts) ].compact.join(" · ")
    elsif coming && result.value != "paid"
      amounts ? "Next: #{accounting_cents(coming["catch_up_cents"])} by #{accounting_date(coming["due_on"])}" : "Next: #{coming["name"]}"
    end
  end

  MILESTONE_STATES = {
    met: { label: "Met", color: "success", icon: "check" },
    missed: { label: "Missed", color: "danger", icon: "xmark" },
    next: { label: "Next", color: "primary", icon: "arrow-right" },
    later: { label: "Coming up", color: "secondary", icon: "clock" }
  }.freeze

  # The result's milestones (or its plan's) as steps for the Account card:
  # name, date, state (met, missed, next or later) and what it takes to meet
  # it. The first one still ahead is next; a milestone is missed once its
  # date and the rule's grace days have passed.
  def accounting_milestone_steps(result, today: Date.current)
    ahead = false
    result.milestones.map do |milestone|
      due = Date.iso8601(milestone["due_on"].to_s)
      state = if milestone["met"] then :met
      elsif due + result.rule.grace_period < today then :missed
      else
        ahead ? :later : :next
      end
      ahead ||= state == :next
      milestone.merge("state" => state, "date" => due)
    end
  end

  # "Updated 25 Nov, 9:36 am".
  def accounting_updated_at(time)
    "Updated #{l(time, format: "%-d %b, %-l:%M %P")}"
  end

  # An invoice's public label ("Invoice 1114 · Membership Dues") as its
  # number and what it was for.
  def accounting_invoice_parts(label)
    number, what = label.to_s.split(" · ", 2)
    [ number, what ]
  end

  # The share of what was charged that's paid, as a whole percent.
  def accounting_paid_percent(result)
    charged = result.detail(:charged_cents).to_i
    return 0 unless charged.positive?

    (result.detail(:paid_cents).to_i * 100.0 / charged).floor.clamp(0, 100)
  end

  # "Reminders: 3 days before each milestone, then every 7 days while
  # overdue; last sent Mar 1", for admins. nil for a rule that isn't a
  # balance rule.
  def accounting_reminders_line(rule)
    return unless rule.balance?
    return "Reminders: off" unless rule.reminders?

    parts = []
    parts << "#{pluralize(rule.remind_days_before.to_i, "day")} before each milestone" if rule.remind_days_before.present?
    parts << "every #{pluralize(rule.overdue_every_days.to_i, "day")} while overdue" if rule.overdue_every_days.present?
    text = "Reminders: #{parts.join(", then ")}"
    last = rule.reminders.maximum(:sent_at)
    last ? "#{text}; last sent #{l(last.to_date, format: :short)}" : text
  end

  # Who sees a payment plan, by the rule's levels: the person and their
  # guardians see its names and dates when the rule shows them the result,
  # and its amounts when it shows them amounts. Everyone else sees only the
  # status.
  def accounting_plan_audience(rule)
    names = accounting_plan_viewers(rule.read_permission)
    amounts = accounting_plan_viewers(rule.amount_permission) & names
    return "On this rule's settings only admins see the plan; everyone else who sees the result sees only the status." if names.empty?

    seen = "#{names.to_sentence.upcase_first} #{names.one? && names.first == "the person" ? "sees" : "see"} the plan's names and dates"
    seen += if amounts == names then " and amounts"
    elsif amounts.any? then ", and #{amounts.to_sentence} its amounts too"
    else ", but not its amounts"
    end
    "#{seen}. Everyone else who sees the result sees only the status."
  end

  def accounting_plan_viewers(level)
    [ ("the person" if AudienceLevels.reaches?(level, :subject)), ("their guardians" if AudienceLevels.reaches?(level, :guardian)) ].compact
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
