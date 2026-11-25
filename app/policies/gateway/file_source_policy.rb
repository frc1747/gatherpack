class Gateway
  class FileSourcePolicy < ArchitectPolicy
    # File sources take no webhooks; verify_webhook refuses every request.
    def webhook?
      true
    end
  end
end
