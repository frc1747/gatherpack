class Gateway
  class QuickbooksGatewayPolicy < ArchitectPolicy
    def webhook?
      true
    end
  end
end
