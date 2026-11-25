# Marks each Family page ward card that has account rows for the viewer, and
# counts an overdue account in what needs the viewer.
module MyGatherpack::AccountingFamilyCards
  def family_cards
    @accounting_family_cards ||= super.each do |card|
      row = my_gatherpack_account_row(card.ward)
      card.accounting = row.present?
      card.needs_you += row.lines.count { |line| line.result.value == "overdue" } if row
    end
  end
end
