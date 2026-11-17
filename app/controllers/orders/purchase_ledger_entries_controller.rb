module Orders
  # Record in ledger, for a purchase recorded without an entry (spec §6):
  # a treasurer adds it later from the purchase page.
  class PurchaseLedgerEntriesController < BaseController
    before_action :require_ledger

    # POST /orders/purchases/1/ledger_entry
    def create
      purchase = authorize policy_scope(Purchase).find(params[:purchase_id]), :record_in_ledger?
      ledger = Ledger.find_by(id: params[:ledger_id])
      Orders::RecordInLedger.new(purchase, ledger: ledger, by: current_user.person).call
      redirect_to orders_purchase_path(purchase), notice: "Recorded in #{ledger.name}."
    end

    private

    def require_ledger
      redirect_to orders_purchases_path, notice: "The ledger is turned off" unless Orders::LedgerRecording.ledger_on?
    end
  end
end
