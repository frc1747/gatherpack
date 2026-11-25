# Account status on the My GatherPack home page and the Family page: one row
# per person, with each rule's result the viewer may see for them. Who sees
# what comes from Accounting::Access and Accounting::RuleAccess, the same as
# the person's Account tab, so the three always agree.
module MyGatherpackAccountingHelper
  # One rule's line in a row. +amounts+ says whether the viewer may see the
  # balance; +pay_url+ is set only when they may also pay online.
  AccountLine = Struct.new(:result, :amounts, :pay_url, keyword_init: true) do
    def rule
      result.rule
    end
  end

  # One person's row. +ward+ is their first name when they aren't the viewer.
  AccountRow = Struct.new(:person, :ward, :lines, keyword_init: true) do
    # The row's one solid button: the first charge the viewer may pay.
    def pay_url
      lines.map(&:pay_url).compact.first
    end
  end

  # The viewer's own row, then one per ward, leaving out anyone with nothing
  # to show.
  def my_gatherpack_account_rows
    @my_gatherpack_account_rows ||= begin
      viewer = current_user&.person
      if viewer && GatherPack::Features.enabled?(:accounting)
        wards = viewer.wards.to_a.sort_by { |ward| [ my_gatherpack_account_name(ward).downcase, ward.id ] }
        [ viewer, *wards ].filter_map { |person| my_gatherpack_account_row(person) }
      else
        []
      end
    end
  end

  # A row for one person, or nil when the viewer may see none of their
  # results. Turned-off rules and errors stay off these pages, even for
  # admins: they're on the Account tab.
  def my_gatherpack_account_row(person)
    viewer = current_user&.person
    return unless viewer && person && GatherPack::Features.enabled?(:accounting)

    @my_gatherpack_account_row ||= {}
    return @my_gatherpack_account_row[person.id] if @my_gatherpack_account_row.key?(person.id)

    results = Accounting::Access.visible_results(current_user, person).select { |result| result.rule.enabled? && !result.error? }
    lines = results.map do |result|
      amounts = Accounting::RuleAccess.new(viewer, person, result.rule).can_see_amounts?
      AccountLine.new(result: result, amounts: amounts, pay_url: (my_gatherpack_account_pay_url(result) if amounts))
    end
    @my_gatherpack_account_row[person.id] = lines.any? ? AccountRow.new(person: person, lines: lines,
      ward: (my_gatherpack_account_name(person) unless person.id == viewer.id)) : nil
  end

  # What a line says after the status: the balance when the viewer may see
  # it, then the milestone line. Labels are public ones only.
  def my_gatherpack_account_detail(line)
    result = line.result
    parts = []
    if line.amounts && line.rule.balance? && result.value != "not_invoiced" && result.value != "paid"
      parts << "Balance remaining #{accounting_cents(result.amount_cents)}"
    end
    parts << accounting_milestone_line(result, amounts: line.amounts) if line.rule.balance?
    parts.compact_blank.join(" · ")
  end

  private
    # The first charge with a balance and a pay link, when the rule shows
    # pay links and the source has them.
    def my_gatherpack_account_pay_url(result)
      return unless result.rule.pay_links? && result.amount_cents.to_i.positive?

      result.charges.find { |charge| charge["pay_url"].present? && charge["balance_cents"].to_i.positive? }&.dig("pay_url")
    end

    def my_gatherpack_account_name(person)
      person.first_name.presence || person.identifier_name
    end
end
