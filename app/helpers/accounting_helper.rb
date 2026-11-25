module AccountingHelper
  ROLE_NAMES = {
    "customer" => "Customer", "charge" => "Charge", "receipt" => "Receipt", "payment" => "Payment", "credit" => "Credit",
    "refund" => "Refund", "item" => "Item", "category" => "Category", "other" => "Other"
  }.freeze

  def accounting_role_name(role)
    ROLE_NAMES.fetch(role.to_s, role.to_s.humanize)
  end

  def accounting_cents(cents)
    cents.nil? ? "" : Money.new(cents).format
  end
end
