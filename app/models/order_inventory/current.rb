# Per web request state for the bridge: put-aways that couldn't be done,
# shown with the delivery's notice (OrderInventory::DeliveryNotices).
module OrderInventory
  class Current < ActiveSupport::CurrentAttributes
    attribute :problems, default: -> { [] }
  end
end
