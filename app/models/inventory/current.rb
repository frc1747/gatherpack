# Per web request memo for Inventory::Access, cleared by Rails between
# requests (and between tests).
module Inventory
  class Current < ActiveSupport::CurrentAttributes
    attribute :access, default: -> { {} }
  end
end
