class Gateway
  class SmtpSendingGatewayPolicy < ArchitectPolicy
    def webhook?
      true
    end
  end
end
