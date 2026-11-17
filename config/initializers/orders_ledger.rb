# Orders with the upstream Ledger and Budgets features (spec §6). Deleting a
# ledger entry made from a purchase puts the purchase back to "Not in
# ledger", and deleting a Budget unlinks the funding sources linked to it,
# instead of the foreign keys refusing the delete.
Rails.application.config.to_prepare do
  LedgerEntry.has_one :purchase, dependent: :nullify, inverse_of: :ledger_entry
  Budget.has_many :funding_sources, dependent: :nullify, inverse_of: :budget
end
