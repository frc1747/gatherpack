# Receipts are linked here rather than straight to Active Storage, whose
# links open for anyone who holds them. This checks that the user can see
# the ledger entry, then redirects to a service URL that expires in minutes.
class LedgerEntryReceiptsController < InternalController
  include ActiveStorage::SetCurrent

  # GET /ledgers/1/ledger_entries/1/receipts/1
  def show
    ledger = authorize policy_scope(Ledger).find(params[:ledger_id])
    ledger_entry = authorize policy_scope(ledger.ledger_entries).find(params[:ledger_entry_id])
    receipt = ledger_entry.receipts_attachments.find(params[:id])

    redirect_to receipt.url, allow_other_host: true
  end
end
