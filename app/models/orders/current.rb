# Per web request memo for Orders::Access and Orders::WaitingOn, cleared by
# Rails between requests (and between tests).
module Orders
  class Current < ActiveSupport::CurrentAttributes
    attribute :access, default: -> { {} }
    attribute :waiting_on, default: -> { {} }
  end
end
