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
end
