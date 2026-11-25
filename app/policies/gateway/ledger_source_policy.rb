class Gateway
  class LedgerSourcePolicy < ArchitectPolicy
    # Ledger sources take no webhooks; verify_webhook refuses every request.
    def webhook?
      true
    end
  end
end
