# Marks each Family page ward card that has account rows for the viewer.
module MyGatherpack::AccountingFamilyCards
  def family_cards
    super.each { |card| card.accounting = my_gatherpack_account_row(card.ward).present? }
  end
end
